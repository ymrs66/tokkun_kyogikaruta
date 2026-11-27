// test/rank_test.dart
//
// Phase 2：ミリ秒計測に合わせてランク基準を0.5秒ずつ緩めた（S 1.5／A 2.0／B 2.5／C 3.5秒）。
// 境界値の詳しいテストは test/domain/rank_policy_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/providers/game_state.dart';

void main() {
  group('calcRank（Phase 2 の基準。game_state.dart からも使える）', () {
    test('S：正答率100% かつ 平均1.5秒以内', () {
      expect(calcRank(100, 0), Rank.S);
      expect(calcRank(100, 1500), Rank.S);
      expect(calcRank(100, 1600), Rank.A);
    });
    test('A：正答率95%以上 かつ 平均2.0秒以内', () {
      expect(calcRank(95, 2000), Rank.A);
      expect(calcRank(95, 2100), Rank.B);
      expect(calcRank(90, 1500), Rank.B);
    });
    test('B・C・D', () {
      expect(calcRank(90, 2500), Rank.B);
      expect(calcRank(90, 2600), Rank.C);
      expect(calcRank(80, 3500), Rank.C);
      expect(calcRank(80, 3600), Rank.D);
      expect(calcRank(70, 0), Rank.D);
    });
    test('旧基準で S だった「切り捨て1秒」の人は、ミリ秒でもおおむね S（+0.5秒）', () {
      // 旧：1.9秒で取っても1秒と記録 → 平均1.0秒でS。新：実測1.4〜1.5秒でS。
      expect(calcRank(100, 1450), Rank.S);
    });
  });
}
