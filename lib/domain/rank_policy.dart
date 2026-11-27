// lib/domain/rank_policy.dart
//
// ランクの基準値は、このファイルの [RankPolicy.rules] の1か所にまとめる。
// 結果画面・遊び方・テストはここを参照する。

enum Rank { S, A, B, C, D }

/// 1つのランクの条件
class RankRule {
  const RankRule(this.rank, {required this.minAccuracy, required this.maxAvgMs});
  final Rank rank;

  /// 最終正答率（％）がこれ以上
  final int minAccuracy;

  /// 平均取得時間（ミリ秒）がこれ以下（「以内」）
  final int maxAvgMs;
}

class RankPolicy {
  RankPolicy._();

  /// ランク基準（暫定。総合テストの実測で必要なら調整する）
  /// ミリ秒計測に合わせて、1.0.11 の基準（S 1.0／A 1.5／B 2.0／C 3.0秒）から0.5秒ずつ緩めた。
  static const List<RankRule> rules = [
    RankRule(Rank.S, minAccuracy: 100, maxAvgMs: 1500),
    RankRule(Rank.A, minAccuracy: 95, maxAvgMs: 2000),
    RankRule(Rank.B, minAccuracy: 90, maxAvgMs: 2500),
    RankRule(Rank.C, minAccuracy: 80, maxAvgMs: 3500),
  ];

  /// 旧計測（1秒単位の切り捨て）の平均を、ミリ秒計測と比べるときの補正
  static const int legacyTimingOffsetMs = 500;

  /// 計測方式の版（1 = 旧計測：秒の切り捨て、2 = ミリ秒）
  static const int currentTimingVersion = 2;
}

/// ランクを求める。[avgMs] が null（正解0回＝平均なし）なら秒数の条件を満たさない（D）。
Rank calcRank(int accuracy, int? avgMs) {
  if (avgMs == null) return Rank.D;
  for (final r in RankPolicy.rules) {
    if (accuracy >= r.minAccuracy && avgMs <= r.maxAvgMs) return r.rank;
  }
  return Rank.D;
}

/// 秒の表示用（例：1500 → "1.5"）
String formatSecondsLimit(int ms) {
  final s = ms / 1000;
  return s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toString();
}
