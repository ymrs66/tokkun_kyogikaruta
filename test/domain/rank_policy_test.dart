// test/domain/rank_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/domain/practice_record.dart';
import 'package:tokkun_kyogikaruta/domain/rank_policy.dart';

PracticeRecord rec({
  Rank rank = Rank.B,
  int accuracy = 90,
  int? avgMs = 2000,
  int timingVersion = 2,
  bool reference = false,
  int karafuda = 0,
}) =>
    PracticeRecord(
      rank: rank,
      accuracy: accuracy,
      avgMs: avgMs,
      successCount: accuracy ~/ 10,
      deduction: 0,
      totalQuestions: 10,
      karafudaPercent: karafuda,
      otetsukiPenalty: false,
      timingVersion: timingVersion,
      isReference: reference,
      sessionId: 's',
      playedAt: DateTime(2026, 11, 27),
    );

void main() {
  group('ランクの境界値（暫定基準 S1.5／A2.0／B2.5／C3.5秒）', () {
    test('S：100% かつ 1500ms 以内（1500 は S、1501 は A）', () {
      expect(calcRank(100, 0), Rank.S);
      expect(calcRank(100, 1500), Rank.S);
      expect(calcRank(100, 1501), Rank.A);
      expect(calcRank(99, 1000), Rank.A);
    });
    test('A：95% 以上 かつ 2000ms 以内', () {
      expect(calcRank(95, 2000), Rank.A);
      expect(calcRank(95, 2001), Rank.B);
      expect(calcRank(94, 1000), Rank.B);
    });
    test('B：90% 以上 かつ 2500ms 以内', () {
      expect(calcRank(90, 2500), Rank.B);
      expect(calcRank(90, 2501), Rank.C);
      expect(calcRank(89, 1000), Rank.C);
    });
    test('C：80% 以上 かつ 3500ms 以内', () {
      expect(calcRank(80, 3500), Rank.C);
      expect(calcRank(80, 3501), Rank.D);
      expect(calcRank(79, 1000), Rank.D);
    });
    test('平均なし（正解0回）は D（0秒の優秀な記録として扱わない）', () {
      expect(calcRank(100, null), Rank.D);
      expect(calcRank(0, null), Rank.D);
    });
    test('基準値は1か所（RankPolicy.rules）にある', () {
      expect(RankPolicy.rules.map((r) => r.maxAvgMs), [1500, 2000, 2500, 3500]);
      expect(RankPolicy.rules.map((r) => r.minAccuracy), [100, 95, 90, 80]);
    });
  });

  group('最高記録の比較（ランク → 正答率 → 平均）', () {
    test('ランクが高いほうが上（正答率・平均に関係なく）', () {
      expect(compareRecords(rec(rank: Rank.A, accuracy: 95, avgMs: 2000),
              rec(rank: Rank.B, accuracy: 100, avgMs: 100)),
          greaterThan(0));
    });
    test('同じランクなら正答率が高いほうが上', () {
      expect(compareRecords(rec(accuracy: 100), rec(accuracy: 90)),
          greaterThan(0));
    });
    test('正答率も同じなら平均が短いほうが上', () {
      expect(compareRecords(rec(avgMs: 1999), rec(avgMs: 2000)), greaterThan(0));
    });
    test('すべて同じなら 0（既存を残す）', () {
      expect(compareRecords(rec(), rec()), 0);
      expect(isNewBest(rec(), rec()), isFalse);
    });
    test('平均なしは平均ありより下（0秒として比べない）', () {
      expect(compareRecords(rec(avgMs: null), rec(avgMs: 9000)), lessThan(0));
      expect(compareRecords(rec(avgMs: 9000), rec(avgMs: null)), greaterThan(0));
      expect(compareRecords(rec(avgMs: null), rec(avgMs: null)), 0);
    });
    test('旧計測は比較のときだけ +500ms（保存値は変えない）', () {
      final legacy = rec(avgMs: 1000, timingVersion: 1);
      expect(legacy.avgMs, 1000);
      expect(legacy.comparableAvgMs, 1500);
      expect(compareRecords(rec(avgMs: 1499), legacy), greaterThan(0));
      expect(compareRecords(rec(avgMs: 1500), legacy), 0);
      expect(compareRecords(rec(avgMs: 1501), legacy), lessThan(0));
    });
    test('参考記録は最高記録を更新しない', () {
      expect(isNewBest(rec(rank: Rank.S, reference: true), null), isFalse);
      expect(isNewBest(rec(rank: Rank.S, reference: true), rec(rank: Rank.D)),
          isFalse);
      expect(isNewBest(rec(rank: Rank.S), null), isTrue);
    });
  });

  group('JSON・既存キーからの復元', () {
    test('JSON の往復で同じ値', () {
      final r = rec(avgMs: null, karafuda: 30);
      final back = PracticeRecord.fromJson(r.toJson());
      expect(back.avgMs, isNull);
      expect(back.karafudaPercent, 30);
      expect(back.category, RecordCategory.karafuda);
      expect(compareRecords(back, r), 0);
    });
    test('壊れた JSON は FormatException', () {
      expect(() => PracticeRecord.fromJson('x'), throwsFormatException);
      expect(() => PracticeRecord.fromJson({'rank': 'Z'}), throwsFormatException);
      final bad = rec().toJson()..['accuracy'] = 150;
      expect(() => PracticeRecord.fromJson(bad), throwsFormatException);
    });
    test('既存キー：正答率0%なら平均なし、それ以外は秒→ms（旧計測）', () {
      final zero =
          PracticeRecord.fromLegacy(rankName: 'D', accuracy: 0, avgSec: 0.0)!;
      expect(zero.avgMs, isNull);
      final fast =
          PracticeRecord.fromLegacy(rankName: 'S', accuracy: 100, avgSec: 0.0)!;
      expect(fast.avgMs, 0);
      expect(fast.comparableAvgMs, 500);
      expect(fast.timingVersion, 1);
      expect(PracticeRecord.fromLegacy(rankName: null, accuracy: 1, avgSec: 1),
          isNull);
    });
  });
}
