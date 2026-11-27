// lib/domain/practice_record.dart
import 'rank_policy.dart';

/// 最高記録の分類（空札なし／空札あり）
enum RecordCategory { normal, karafuda }

/// 1回の練習の結果（ランク・正答率・平均・条件を1つの組として扱う）。
class PracticeRecord {
  const PracticeRecord({
    required this.rank,
    required this.accuracy,
    required this.avgMs,
    required this.successCount,
    required this.deduction,
    required this.totalQuestions,
    required this.karafudaPercent,
    required this.otetsukiPenalty,
    required this.timingVersion,
    required this.isReference,
    required this.sessionId,
    required this.playedAt,
    this.counts = const {},
    this.mode = PracticeMode.reaction,
    this.memorizeSec,
    this.memorizeUsedSec,
  });

  final Rank rank;

  /// 最終正答率（％）
  final int accuracy;

  /// 平均取得時間（ミリ秒）。null は「平均なし」（正解0回）
  final int? avgMs;

  /// 正答数（正解＋見送り成功。減点前）
  final int successCount;

  /// お手つきペナルティによる減点
  final int deduction;
  final int totalQuestions;

  /// 空札の割合（0 = 空札なし）
  final int karafudaPercent;
  final bool otetsukiPenalty;

  /// 計測方式（1 = 旧計測：秒の切り捨て、2 = ミリ秒）
  final int timingVersion;

  /// 参考記録（途中で中断して続けた練習）
  final bool isReference;
  final String sessionId;
  final DateTime playedAt;

  /// 判定の内訳（反応練習：Verdict.name → 回数、実践練習：MatchOutcome.name と陣別の値）
  final Map<String, int> counts;

  /// 練習の種類（JSON に mode がない既存の記録は反応練習）
  final PracticeMode mode;

  /// 実践練習：設定した暗記時間（秒）
  final int? memorizeSec;

  /// 実践練習：実際に使った暗記時間（秒。「暗記終了」で早く始めた場合は短い）
  final int? memorizeUsedSec;

  RecordCategory get category =>
      karafudaPercent > 0 ? RecordCategory.karafuda : RecordCategory.normal;

  bool get isLegacyTiming => timingVersion < RankPolicy.currentTimingVersion;

  /// 比較に使う平均（旧計測は +0.5秒。保存値は変えない）
  int? get comparableAvgMs => avgMs == null
      ? null
      : (isLegacyTiming ? avgMs! + RankPolicy.legacyTimingOffsetMs : avgMs);

  Map<String, Object?> toJson() => {
        'v': 2,
        'rank': rank.name,
        'accuracy': accuracy,
        'avgMs': avgMs,
        'successCount': successCount,
        'deduction': deduction,
        'totalQuestions': totalQuestions,
        'karafudaPercent': karafudaPercent,
        'otetsukiPenalty': otetsukiPenalty,
        'timingVersion': timingVersion,
        'isReference': isReference,
        'sessionId': sessionId,
        'playedAt': playedAt.toIso8601String(),
        'counts': counts,
        'mode': mode.name,
        if (memorizeSec != null) 'memorizeSec': memorizeSec,
        if (memorizeUsedSec != null) 'memorizeUsedSec': memorizeUsedSec,
      };

  /// JSON から復元する。形式が正しくなければ [FormatException]。
  factory PracticeRecord.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('not a map');
    T req<T>(String k) {
      final v = json[k];
      if (v is! T) throw FormatException('bad field: $k');
      return v;
    }

    final rankName = req<String>('rank');
    final rank = Rank.values.where((r) => r.name == rankName).firstOrNull;
    if (rank == null) throw const FormatException('bad rank');
    final accuracy = req<int>('accuracy');
    if (accuracy < 0 || accuracy > 100) throw const FormatException('bad accuracy');
    final avg = json['avgMs'];
    if (avg != null && (avg is! int || avg < 0)) {
      throw const FormatException('bad avgMs');
    }
    final playedAt = DateTime.tryParse(req<String>('playedAt'));
    if (playedAt == null) throw const FormatException('bad playedAt');
    final countsRaw = json['counts'];
    final counts = <String, int>{};
    if (countsRaw is Map) {
      countsRaw.forEach((k, v) {
        if (k is String && v is int) counts[k] = v;
      });
    }
    final modeName = json['mode'];
    final mode = modeName == null
        ? PracticeMode.reaction
        : PracticeMode.values.where((m) => m.name == modeName).firstOrNull;
    if (mode == null) throw const FormatException('bad mode');
    final mem = json['memorizeSec'];
    final memUsed = json['memorizeUsedSec'];
    return PracticeRecord(
      mode: mode,
      memorizeSec: mem is int ? mem : null,
      memorizeUsedSec: memUsed is int ? memUsed : null,
      rank: rank,
      accuracy: accuracy,
      avgMs: avg as int?,
      successCount: req<int>('successCount'),
      deduction: req<int>('deduction'),
      totalQuestions: req<int>('totalQuestions'),
      karafudaPercent: req<int>('karafudaPercent'),
      otetsukiPenalty: req<bool>('otetsukiPenalty'),
      timingVersion: req<int>('timingVersion'),
      isReference: req<bool>('isReference'),
      sessionId: req<String>('sessionId'),
      playedAt: playedAt,
      counts: counts,
    );
  }

  /// 既存の保存キー（bestRank・bestAccuracy・bestAvgSec）から旧計測の記録を組み立てる。
  /// bestRank がなければ null（記録なし）。
  static PracticeRecord? fromLegacy({
    required String? rankName,
    required int? accuracy,
    required double? avgSec,
  }) {
    if (rankName == null) return null;
    final rank =
        Rank.values.where((r) => r.name == rankName).firstOrNull ?? Rank.D;
    final acc = (accuracy ?? 0).clamp(0, 100);
    // 旧版は正解0回のとき平均 0.0 を保存していた。正答率0％なら「平均なし」とみなす。
    final int? avg =
        (acc == 0 || avgSec == null || avgSec < 0) ? null : (avgSec * 1000).round();
    return PracticeRecord(
      rank: rank,
      accuracy: acc,
      avgMs: avg,
      successCount: (acc / 10).round(),
      deduction: 0,
      totalQuestions: 10,
      karafudaPercent: 0,
      otetsukiPenalty: false,
      timingVersion: 1,
      isReference: false,
      sessionId: 'legacy',
      playedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// a が b より良ければ正、悪ければ負、同じなら 0。
/// 順番：ランク → 正答率 → 平均取得時間（短いほど良い。平均なしは平均ありより悪い）。
int compareRecords(PracticeRecord a, PracticeRecord b) {
  final byRank = b.rank.index - a.rank.index; // S(0) が最上位
  if (byRank != 0) return byRank;
  final byAccuracy = a.accuracy - b.accuracy;
  if (byAccuracy != 0) return byAccuracy;
  final x = a.comparableAvgMs;
  final y = b.comparableAvgMs;
  if (x == null && y == null) return 0;
  if (x == null) return -1;
  if (y == null) return 1;
  return y - x;
}

/// [candidate] で最高記録を更新するか（参考記録は更新しない。同じなら更新しない）。
bool isNewBest(PracticeRecord candidate, PracticeRecord? current) {
  if (candidate.isReference) return false;
  if (current == null) return true;
  return compareRecords(candidate, current) > 0;
}
