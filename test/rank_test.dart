// test/rank_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/providers/game_state.dart';

void main() {
  group('calcRank（1.0.11 の基準）', () {
    test('S：正解率100% かつ 平均1.0秒以内', () {
      expect(calcRank(100, 0.0), Rank.S);
      expect(calcRank(100, 1.0), Rank.S);
      expect(calcRank(100, 1.1), Rank.A);
    });
    test('A：正解率95%以上 かつ 平均1.5秒以内', () {
      expect(calcRank(95, 1.5), Rank.A);
      expect(calcRank(95, 1.6), Rank.B);
      expect(calcRank(90, 1.0), Rank.B);
    });
    test('B・C・D は従来どおり', () {
      expect(calcRank(90, 2.0), Rank.B);
      expect(calcRank(90, 2.1), Rank.C);
      expect(calcRank(80, 3.0), Rank.C);
      expect(calcRank(80, 3.1), Rank.D);
      expect(calcRank(70, 0.0), Rank.D);
    });
  });
}
