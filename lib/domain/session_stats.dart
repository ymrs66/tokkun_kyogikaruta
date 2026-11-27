// lib/domain/session_stats.dart
import 'dart:math';

import 'verdict.dart';

/// 1回の練習の集計。Flutter に依存しない。
class SessionStats {
  SessionStats({required this.totalQuestions, required this.otetsukiPenalty});

  /// 問題数（反応練習は10）
  final int totalQuestions;

  /// お手つきペナルティ（ON：お手つき1回につき正答1問分を引く）
  final bool otetsukiPenalty;

  final Map<Verdict, int> _counts = {for (final v in Verdict.values) v: 0};
  final List<int> _takeMs = [];
  final List<int> _passMs = [];

  /// 判定を1件記録する。[elapsedMs] は読み上げ開始からの時間（正解・見送り成功のときだけ使う）。
  void record(Verdict verdict, {int? elapsedMs}) {
    _counts[verdict] = _counts[verdict]! + 1;
    if (elapsedMs == null) return;
    if (verdict == Verdict.correct) _takeMs.add(elapsedMs);
    if (verdict == Verdict.passOk) _passMs.add(elapsedMs);
  }

  int count(Verdict v) => _counts[v]!;

  /// 判定した問題数
  int get judgedCount => _counts.values.fold(0, (a, b) => a + b);

  /// 正答（正解＋見送り成功）の数。減点前。
  int get successCount => count(Verdict.correct) + count(Verdict.passOk);

  /// お手つきによる減点（ペナルティ OFF なら 0）
  int get deduction => otetsukiPenalty ? count(Verdict.fault) : 0;

  /// 減点後の正答数（0 未満にしない）
  int get finalCorrect => max(0, successCount - deduction);

  /// 最終正答率（％、四捨五入）。ランクはこの値で判定する。
  /// 空札なし・ペナルティなしなら従来の (正解数 / 10 × 100) と同じ。
  int get accuracyPercent =>
      totalQuestions == 0 ? 0 : (finalCorrect * 100 / totalQuestions).round();

  /// 正解（取り札）の反応時間（ミリ秒）
  List<int> get takeMs => List.unmodifiable(_takeMs);

  /// 平均取得時間（ミリ秒）。正解が0回なら null（「平均なし」。0秒とは区別する）
  int? get avgTakeMs => _takeMs.isEmpty
      ? null
      : (_takeMs.reduce((a, b) => a + b) / _takeMs.length).round();

  /// 平均見送り時間（ミリ秒）。見送り成功が0回なら null
  int? get avgPassMs => _passMs.isEmpty
      ? null
      : (_passMs.reduce((a, b) => a + b) / _passMs.length).round();

  /// 判定の内訳（保存・表示用）
  Map<String, int> countsByName() =>
      {for (final v in Verdict.values) v.name: count(v)};
}
