// lib/screens/match_result_screen.dart
//
// 実践練習の結果。表示の順：練習条件 → ランク → 最高記録更新・参考記録 → 最終正答率・平均取得時間
// → 詳細（取得枚数・陣別・お手つき・取り逃し・同陣ミス・見送り成功）→ ボタン
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/match_judge.dart';
import '../domain/match_plan.dart';
import '../providers/game_provider.dart';
import '../providers/game_state.dart' show ResultOutcome;
import '../services/ad_service.dart';
import '../services/gallery_service.dart';
import '../services/orientation_lock.dart';
import '../widgets/back_to_home.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/gallery_award.dart';
import '../widgets/score_card.dart';
import 'match_setup_screen.dart' show memorizeLabel;
import 'result_screen.dart' show ConditionChip, formatAvg;

class MatchResultScreen extends ConsumerStatefulWidget {
  const MatchResultScreen({super.key});

  @override
  ConsumerState<MatchResultScreen> createState() => _MatchResultScreenState();
}

class _MatchResultScreenState extends ConsumerState<MatchResultScreen> {
  ResultOutcome? _outcome;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    OrientationLock.acquirePortrait();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdService.showInterstitialOnce();
      _finalize();
    });
  }

  @override
  void dispose() {
    OrientationLock.releasePortrait();
    super.dispose();
  }

  Future<void> _finalize() async {
    final m = ref.read(matchProvider);
    if (!m.finished) return;
    final outcome = await m.finalizeResult(
      repository: ref.read(scoreRepositoryProvider),
      grantGallery: GalleryService.grantForResult, // 反応練習と共通
    );
    if (!mounted) return;
    setState(() => _outcome = outcome);
    await showGalleryAward(context, outcome);
  }

  void _leave(void Function() action) {
    if (_leaving) return; // 二重に処理しない
    _leaving = true;
    action();
  }

  void _home() => _leave(() {
        ref.read(matchProvider).reset();
        context.go('/');
      });

  void _newPlacement() => _leave(() {
        final m = ref.read(matchProvider);
        m.start(m.config);
        context.go('/match/play');
      });

  void _samePlacement() => _leave(() {
        ref.read(matchProvider).restartSamePlacement();
        context.go('/match/play');
      });

  @override
  Widget build(BuildContext context) {
    final m = ref.read(matchProvider);
    if (m.slots.isEmpty) {
      return BackToHome(child: BackgroundScaffold(child: const SizedBox.shrink()));
    }
    final record = _outcome?.record ?? m.buildRecord();
    final s = m.stats;
    final t = Theme.of(context).textTheme;

    String perSide(Side side) {
      final avg = s.avgTakeMsOn(side);
      return '${s.takenOn(side)} / 6 枚'
          '${avg == null ? '' : '（平均 ${(avg / 1000).toStringAsFixed(2)} 秒）'}';
    }

    final details = <(String, String)>[
      ('取った札', '${s.taken} / $matchFieldCount 枚'),
      ('　自陣', perSide(Side.self)),
      ('　敵陣', perSide(Side.enemy)),
      ('お手つき', '${s.otetsuki}（反対の陣 ${s.count(MatchOutcome.oppositeSide)}・空札 ${s.count(MatchOutcome.karafudaTouched)}）'),
      ('取り逃し', '${s.missed}'),
      ('同陣ミス', '${s.sameSide}（減点なし）'),
      if (m.config.karafudaPercent > 0)
        ('見送り成功', '${s.passSuccess} / ${matchKarafudaCount(m.config.karafudaPercent)}'),
      if (record.memorizeUsedSec != null)
        ('暗記した時間', '${record.memorizeUsedSec} 秒（設定 ${memorizeLabel(record.memorizeSec!)}）'),
    ];

    return BackToHome(
      onBack: _home,
      child: BackgroundScaffold(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ScoreCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('実践練習 結果', style: t.titleLarge),
                    const SizedBox(height: 6),
                    // 1. 練習条件
                    ConditionChip(record: record),
                    const SizedBox(height: 6),
                    // 2. ランク
                    Text('ランク ${record.rank.name}',
                        key: const ValueKey('match-rank'),
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                    // 3. 最高記録・参考記録
                    if (record.isReference)
                      NoticeText(
                        m.samePlacement
                            ? '参考記録：同じ配置での練習のため、最高記録・ギャラリーの対象外です'
                            : '参考記録：途中で中断したため、最高記録・ギャラリーの対象外です',
                        color: const Color(0xFF8D6E00),
                      )
                    else if (_outcome?.save.bestUpdated ?? false)
                      NoticeText(
                          '最高記録を更新しました！（${record.karafudaPercent == 0 ? '空札なし' : '空札 ${record.karafudaPercent}%'}）',
                          color: const Color(0xFF2E7D32)),
                    const SizedBox(height: 10),
                    // 4. 最終正答率・平均取得時間
                    Row(
                      children: [
                        Expanded(
                          child: _BigValue(
                            label: '最終正答率',
                            value: '${record.accuracy}%',
                            note: '(${s.taken}−${s.otetsuki})÷12',
                          ),
                        ),
                        Expanded(
                          child: _BigValue(label: '平均取得時間', value: formatAvg(record.avgMs)),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    // 5. 詳細
                    for (final (k, v) in details) LabelValueRow(label: k, value: v),
                    const SizedBox(height: 14),
                    // 6. ボタン
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('match-home'),
                        onPressed: _home,
                        child: const Text('ホームに戻る'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const ValueKey('match-new'),
                            onPressed: _newPlacement,
                            child: const Text('新しい配置で'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            key: const ValueKey('match-same'),
                            onPressed: _samePlacement,
                            child: const Text('同じ配置で※'),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('※同じ配置でもう一度は参考記録（最高記録・ギャラリーの対象外）',
                          style: t.bodySmall),
                    ),
                    TextButton(
                      onPressed: () => _leave(() {
                        ref.read(matchProvider).reset();
                        context.go('/gallery');
                      }),
                      child: const Text('ギャラリーを見る'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BigValue extends StatelessWidget {
  const _BigValue({required this.label, required this.value, this.note});
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(label, style: t.bodySmall?.copyWith(color: Colors.black54)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        ),
        if (note != null) Text(note!, style: t.bodySmall?.copyWith(color: Colors.black54)),
      ],
    );
  }
}
