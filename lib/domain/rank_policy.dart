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

/// 練習の種類（ランク基準を種類ごとに調整できるようにする）
enum PracticeMode {
  /// 反応練習
  reaction,

  /// 実践練習（Phase 4）
  match,
}

class RankPolicy {
  RankPolicy._();

  /// 反応練習のランク基準（暫定。TestFlight の実機確認を踏まえて調整する）
  /// ミリ秒計測に合わせて、1.0.11 の基準（S 1.0／A 1.5／B 2.0／C 3.0秒）から0.5秒ずつ緩めた。
  static const List<RankRule> rules = [
    RankRule(Rank.S, minAccuracy: 100, maxAvgMs: 1500),
    RankRule(Rank.A, minAccuracy: 95, maxAvgMs: 2000),
    RankRule(Rank.B, minAccuracy: 90, maxAvgMs: 2500),
    RankRule(Rank.C, minAccuracy: 80, maxAvgMs: 3500),
  ];

  /// 実践練習のランク基準（Phase 4。暫定で反応練習と同じ値。個別に調整できる）
  static const List<RankRule> matchRules = rules;

  /// 練習の種類ごとの基準
  static List<RankRule> rulesFor(PracticeMode mode) =>
      mode == PracticeMode.match ? matchRules : rules;

  /// 旧計測（1秒単位の切り捨て）の平均を、ミリ秒計測と比べるときの補正
  static const int legacyTimingOffsetMs = 500;

  /// 計測方式の版（1 = 旧計測：秒の切り捨て、2 = ミリ秒）
  static const int currentTimingVersion = 2;
}

/// ランクを求める。[avgMs] が null（正解0回＝平均なし）なら秒数の条件を満たさない（D）。
Rank calcRank(int accuracy, int? avgMs,
    {PracticeMode mode = PracticeMode.reaction}) {
  if (avgMs == null) return Rank.D;
  for (final r in RankPolicy.rulesFor(mode)) {
    if (accuracy >= r.minAccuracy && avgMs <= r.maxAvgMs) return r.rank;
  }
  return Rank.D;
}

/// 秒の表示用（例：1500 → "1.5"）
String formatSecondsLimit(int ms) {
  final s = ms / 1000;
  return s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toString();
}
