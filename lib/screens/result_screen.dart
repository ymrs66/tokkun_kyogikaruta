import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../widgets/background_scaffold.dart';
import 'package:tokkun_kyogikaruta/services/ad_service.dart';

import '../domain/practice_record.dart';
import '../domain/rank_policy.dart' show PracticeMode;
import '../domain/verdict.dart';
import '../providers/game_provider.dart';
import '../providers/game_state.dart';
import '../services/gallery_service.dart';
import '../widgets/score_card.dart';
import '../widgets/back_to_home.dart';
import '../widgets/gallery_award.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  ResultOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdService.showInterstitialOnce();
      _finalize();
    });
  }

  /// 保存とギャラリー付与（GameState 側で1回だけ行われる。参考記録は付与しない）
  Future<void> _finalize() async {
    final g = ref.read(gameProvider);
    if (!g.finished) return; // リセット後に再表示された場合など
    final outcome = await g.finalizeResult(
      repository: ref.read(scoreRepositoryProvider),
      grantGallery: GalleryService.grantForResult, // 反応練習・実践練習で共通
    );
    if (!mounted) return;
    setState(() => _outcome = outcome);

    await showGalleryAward(context, outcome); // 獲得演出・コンプリート（実践練習と共通）
  }

  bool _leaving = false;

  /// ホームへ戻る（ボタン・戻る操作）。二重に呼ばれても1回だけ処理する
  void _backToTitle() {
    if (_leaving) return;
    _leaving = true;
    ref.read(gameProvider).resetGame();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.read(gameProvider);
    final record = _outcome?.record ?? g.buildRecord();
    final s = g.stats;
    final kara = record.karafudaPercent > 0;
    final theme = Theme.of(context);

    final rows = <(String, String)>[
      if (record.deduction > 0) ...[
        ('正答', '${record.successCount} / ${record.totalQuestions} 問'),
        ('お手つき減点', '−${record.deduction}'),
        ('最終正答率', '${record.accuracy} %'),
      ] else
        ('正答率', '${record.accuracy} %'),
      if (kara) ...[
        ('取り札', '正解 ${s.count(Verdict.correct)} ／ 不正解 ${s.count(Verdict.wrong)}'
            ' ／ 見送りミス ${s.count(Verdict.wrongPass)} ／ 取り逃し ${s.count(Verdict.missed)}'),
        ('空札', '見送り成功 ${s.count(Verdict.passOk)} ／ お手つき ${s.count(Verdict.fault)}'
            ' ／ 未回答 ${s.count(Verdict.noAnswer)}'),
      ],
      ('平均取得時間', formatAvg(record.avgMs)),
      if (kara) ('平均見送り時間', formatAvg(s.avgPassMs)),
    ];

    // 戻る操作：獲得ダイアログが出ていればダイアログを閉じるだけ、なければゲームをリセットしてホームへ
    return BackToHome(
      onBack: _backToTitle,
      child: BackgroundScaffold(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ScoreCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('--- 結果 ---', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      ConditionChip(record: record),
                      const SizedBox(height: 10),
                      for (final (k, v) in rows) LabelValueRow(label: k, value: v),
                      const SizedBox(height: 8),
                      Text('ランク : ${record.rank.name}', style: const TextStyle(fontSize: 32)),
                      if (record.isReference)
                        const NoticeText(
                          '参考記録：途中で中断したため、最高記録・ギャラリーの対象外です',
                          color: Color(0xFF8D6E00),
                        )
                      else if (_outcome?.save.bestUpdated ?? false)
                        const NoticeText('最高記録を更新しました！', color: Color(0xFF2E7D32)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _backToTitle,
                        child: const Text('ホームに戻る'),
                      ),
                      TextButton(
                        onPressed: () => context.go('/gallery'),
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

/// 平均時間の表示（平均なしは「—」）
String formatAvg(int? ms) => ms == null ? '—' : '${(ms / 1000).toStringAsFixed(2)} 秒';

/// 練習条件の表示（空札の有無・割合・ペナルティ）
class ConditionChip extends StatelessWidget {
  const ConditionChip({super.key, required this.record});
  final PracticeRecord record;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (record.mode == PracticeMode.match) {
      // 実践練習：お手つきの減点は常にあるので表示しない。暗記時間を添える
      final mem = record.memorizeSec;
      text = '${record.karafudaPercent > 0 ? '空札 ${record.karafudaPercent}%' : '空札なし'}'
          '${mem == null ? '' : '・暗記 ${mem < 60 ? '$mem秒' : '${mem ~/ 60}分'}'}';
    } else {
      text = record.karafudaPercent > 0
          ? '空札あり ${record.karafudaPercent}%${record.otetsukiPenalty ? '・お手つきペナルティ' : ''}'
          : '空札なし';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
