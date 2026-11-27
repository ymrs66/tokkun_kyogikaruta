// lib/screens/match_setup_screen.dart
//
// 実践練習の開始画面：暗記時間・空札の割合（前回の値を初期値にする）と総出題数の説明。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../domain/match_plan.dart';
import '../providers/game_provider.dart';
import '../providers/match_state.dart';
import '../providers/settings_provider.dart';
import '../services/orientation_lock.dart';
import '../widgets/back_to_home.dart';
import '../widgets/background_scaffold.dart';
import '../widgets/score_card.dart';

/// 1回の読みにかかる時間の目安（カウントダウン3秒＋取るまで＋判定表示）。実機の確認で調整する
const double matchSecondsPerRead = 6.5;

/// 練習時間の目安（暗記を除く。0.5分刻み）
String matchDurationLabel(int percent) {
  final min = matchTotalReads(percent) * matchSecondsPerRead / 60;
  final halves = (min * 2).round();
  final whole = halves ~/ 2;
  return halves.isOdd ? (whole == 0 ? '約30秒' : '約$whole分半') : '約$whole分';
}

/// 暗記時間の表示
String memorizeLabel(int sec) => sec < 60 ? '$sec秒' : '${sec ~/ 60}分';

class MatchSetupScreen extends ConsumerStatefulWidget {
  const MatchSetupScreen({super.key});

  @override
  ConsumerState<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends ConsumerState<MatchSetupScreen> {
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    OrientationLock.acquirePortrait();
  }

  @override
  void dispose() {
    OrientationLock.releasePortrait();
    super.dispose();
  }

  void _start() {
    if (_starting) return; // 二重に始めない
    _starting = true;
    final s = ref.read(settingsProvider);
    ref.read(matchProvider).start(MatchConfig(
          memorizeSec: s.matchMemorizeSec,
          karafudaPercent: s.matchKarafudaPercent,
        ));
    context.go('/match/play');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final t = Theme.of(context).textTheme;
    final percent = s.matchKarafudaPercent;
    final k = matchKarafudaCount(percent);
    final total = matchTotalReads(percent);
    final summary = k == 0
        ? '全$total問（場の札12枚）・目安 ${matchDurationLabel(percent)}（暗記を除く）'
        : '全$total問（場の札12枚＋空札$k枚）・目安 ${matchDurationLabel(percent)}（暗記を除く）';

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ScoreCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall?.copyWith(color: Colors.black54)),
                const SizedBox(height: 6),
                ...children,
              ],
            ),
          ),
        );

    return BackToHome(
      child: BackgroundScaffold(
        appBar: homeAppBar(context, '実践練習'),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  section('場の札', [
                    const Text('自陣6枚・敵陣6枚（12枚）。札の位置は最後まで変わりません。'),
                  ]),
                  section('暗記時間', [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: [
                          for (final sec in matchMemorizeSecOptions)
                            ButtonSegment(value: sec, label: Text(memorizeLabel(sec))),
                        ],
                        selected: {s.matchMemorizeSec},
                        onSelectionChanged: (v) => notifier.setMatchMemorizeSec(v.first),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('「暗記終了」でいつでも始められます。', style: t.bodySmall),
                  ]),
                  section('空札', [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 0, label: Text('なし')),
                          ButtonSegment(value: 30, label: Text('30%')),
                          ButtonSegment(value: 50, label: Text('50%')),
                        ],
                        selected: {percent},
                        onSelectionChanged: (v) => notifier.setMatchKarafudaPercent(v.first),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(summary,
                        key: const ValueKey('match-summary'),
                        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    if (k > 0)
                      Text('空札では札に触れず「見送り」を押すか、そのまま待ちます。'
                          '${percent == 30 ? '（30% はおおよその割合です）' : ''}',
                          style: t.bodySmall),
                  ]),
                  section('ルール', [
                    Text(
                      '※競技かるたの正式ルールではなく、手軽に練習するための簡易ルールです。\n'
                      '・同じ陣の別の札：同陣ミス（減点なし・そのまま取れます）\n'
                      '・反対の陣の札・空札で札を押す：お手つき（1回につき1枚分を差し引き）\n'
                      '・時間切れ（10秒）・場にある札で見送り：取り逃し',
                      style: t.bodySmall,
                    ),
                  ]),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      key: const ValueKey('match-start'),
                      onPressed: _start,
                      child: const Text('はじめる', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
