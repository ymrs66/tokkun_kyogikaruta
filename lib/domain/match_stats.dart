// lib/domain/match_stats.dart
//
// 実践練習の集計。Flutter に依存しない。
//
// 最終正答率 ＝ max(0, 取った札 − お手つき) ÷ 12 × 100（四捨五入した整数。ランクもこの整数で判定する）
// 平均取得時間 ＝ 正解した札だけの平均（正解0枚なら平均なし → D）
import 'dart:math';

import 'match_judge.dart';
import 'match_plan.dart';
import 'rank_policy.dart';

class MatchStats {
  final Map<MatchOutcome, int> _counts = {for (final o in MatchOutcome.values) o: 0};
  final Map<Side, List<int>> _takeMs = {Side.self: [], Side.enemy: []};
  final Map<Side, int> _missedBySide = {Side.self: 0, Side.enemy: 0};

  /// 判定を1件記録する。[side] は読まれた場の札の陣（空札は null）。
  /// [elapsedMs] は正解のときの取得時間。
  void record(MatchOutcome o, {Side? side, int? elapsedMs}) {
    _counts[o] = _counts[o]! + 1;
    if (o == MatchOutcome.correct && side != null && elapsedMs != null) {
      _takeMs[side]!.add(elapsedMs);
    }
    if (o.isMissed && side != null) _missedBySide[side] = _missedBySide[side]! + 1;
  }

  /// 同陣ミスを取り消す（中断で取り消した読みの分）
  void undoSameSide(int n) {
    _counts[MatchOutcome.sameSide] = max(0, _counts[MatchOutcome.sameSide]! - n);
  }

  int count(MatchOutcome o) => _counts[o]!;

  /// 取った札
  int get taken => count(MatchOutcome.correct);
  int takenOn(Side s) => _takeMs[s]!.length;
  int missedOn(Side s) => _missedBySide[s]!;

  /// お手つき（反対の陣＋空札）
  int get otetsuki => count(MatchOutcome.oppositeSide) + count(MatchOutcome.karafudaTouched);

  /// 取り逃し（反対の陣のお手つき・時間切れ・見送り）
  int get missed =>
      count(MatchOutcome.oppositeSide) + count(MatchOutcome.timeUp) + count(MatchOutcome.passOnField);
  int get sameSide => count(MatchOutcome.sameSide);
  int get passSuccess => count(MatchOutcome.passOk) + count(MatchOutcome.waitOk);

  /// 判定を終えた読みの数（同陣ミスは数えない）
  int get finishedReads =>
      MatchOutcome.values.where((o) => o.endsRead).fold(0, (a, o) => a + count(o));

  /// 減点後の取得数（0 未満にしない）
  int get effectiveTaken => max(0, taken - otetsuki);

  /// 最終正答率（％、四捨五入の整数）
  int get accuracyPercent => (effectiveTaken * 100 / matchFieldCount).round();

  List<int> get _allTake => [..._takeMs[Side.self]!, ..._takeMs[Side.enemy]!];

  int? _avg(List<int> l) =>
      l.isEmpty ? null : (l.reduce((a, b) => a + b) / l.length).round();

  /// 平均取得時間（ミリ秒）。正解0枚なら null
  int? get avgTakeMs => _avg(_allTake);
  int? avgTakeMsOn(Side s) => _avg(_takeMs[s]!);

  Rank get rank => calcRank(accuracyPercent, avgTakeMs, mode: PracticeMode.match);

  /// 保存用の内訳
  Map<String, int> countsByName() => {
        for (final o in MatchOutcome.values) o.name: count(o),
        'selfTaken': takenOn(Side.self),
        'enemyTaken': takenOn(Side.enemy),
        'selfMissed': missedOn(Side.self),
        'enemyMissed': missedOn(Side.enemy),
        if (avgTakeMsOn(Side.self) != null) 'selfAvgMs': avgTakeMsOn(Side.self)!,
        if (avgTakeMsOn(Side.enemy) != null) 'enemyAvgMs': avgTakeMsOn(Side.enemy)!,
      };
}
