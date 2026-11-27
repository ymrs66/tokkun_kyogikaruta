// test/domain/match_domain_test.dart
//
// 実践練習（12枚固定）の配置・読み順・判定・集計・ランク
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/data/cards.dart';
import 'package:tokkun_kyogikaruta/domain/match_judge.dart';
import 'package:tokkun_kyogikaruta/domain/match_plan.dart';
import 'package:tokkun_kyogikaruta/domain/match_stats.dart';
import 'package:tokkun_kyogikaruta/domain/rank_policy.dart';

void main() {
  group('空札の数と総出題数（U1）', () {
    test('なし 12問／30% 17問（空札5）／50% 24問（空札12）', () {
      expect(matchKarafudaCount(0), 0);
      expect(matchKarafudaCount(30), 5); // 12×0.3÷0.7 = 5.14 → 5
      expect(matchKarafudaCount(50), 12);
      expect(matchTotalReads(0), 12);
      expect(matchTotalReads(30), 17);
      expect(matchTotalReads(50), 24);
    });
    test('選択肢にない割合は空札なし', () {
      expect(matchKarafudaCount(20), 0);
      expect(matchKarafudaCount(100), 0);
    });
  });

  group('配置と読み順（U2・U3）', () {
    for (final percent in matchKarafudaPercentOptions) {
      test('空札 $percent%：1,000回とも 場の札12枚が1回ずつ、空札は場にない札から重複なし、最後は場の札', () {
        for (var seed = 0; seed < 1000; seed++) {
          final plan = buildMatchPlan(allCards: cards, karafudaPercent: percent, rng: Random(seed));
          expect(plan.slots.length, 12);
          expect(plan.slots.where((s) => s.side == Side.self).length, 6);
          expect(plan.slots.where((s) => s.side == Side.enemy).length, 6);
          expect(plan.reads.length, matchTotalReads(percent));
          final ids = plan.reads.map((r) => r.card.id).toList();
          expect(ids.toSet().length, ids.length, reason: '同じ札を二度読まない');
          final field = plan.reads.where((r) => !r.isKarafuda).map((r) => r.slotIndex).toSet();
          expect(field, {for (var i = 0; i < 12; i++) i});
          final onField = {for (final s in plan.slots) s.card.id};
          for (final r in plan.reads.where((r) => r.isKarafuda)) {
            expect(onField.contains(r.card.id), isFalse);
          }
          expect(plan.reads.last.isKarafuda, isFalse, reason: '最後は必ず場の札');
        }
      });
    }

    test('陣ごとに 横3×縦2、位置の番号は一意', () {
      final plan = buildMatchPlan(allCards: cards, karafudaPercent: 30, rng: Random(1));
      for (final side in Side.values) {
        final pos = plan.slots.where((s) => s.side == side).map((s) => (s.row, s.col)).toSet();
        expect(pos, {for (var r = 0; r < 2; r++) for (var c = 0; c < 3; c++) (r, c)});
      }
      expect(plan.slots.map((s) => s.index).toList(), List.generate(12, (i) => i));
    });

    test('同じ配置でもう一度：位置と札は同じ、読み順だけ作り直す', () {
      final a = buildMatchPlan(allCards: cards, karafudaPercent: 50, rng: Random(3));
      final b = buildMatchPlan(
          allCards: cards, karafudaPercent: 50, rng: Random(4), keepSlots: a.slots);
      expect(b.slots, same(a.slots));
      expect(b.reads.length, 24);
      expect(b.reads.last.isKarafuda, isFalse);
    });
  });

  group('中断した読みの入れ直し（U7）', () {
    final f1 = ReadItem(cards[0], slotIndex: 0);
    final f2 = ReadItem(cards[1], slotIndex: 1);
    final k1 = ReadItem(cards[50]);
    final k2 = ReadItem(cards[51]);

    test('最後の場の札は最後のまま', () {
      expect(reinsertInterrupted([k1, k2], f1, Random(0)).last, f1);
    });
    test('残りがなければ読み直し', () {
      expect(reinsertInterrupted([], f1, Random(0)), [f1]);
    });
    test('それ以外は最後の場の札より前、できればすぐ次ではない位置', () {
      for (var seed = 0; seed < 200; seed++) {
        final r = reinsertInterrupted([k1, k2, f2], f1, Random(seed));
        expect(r.length, 4);
        expect(r.last, f2);
        expect(r.indexOf(f1), inInclusiveRange(1, 2));
      }
      final one = reinsertInterrupted([f2], k1, Random(0));
      expect(one, [k1, f2]);
    });
  });

  group('判定（U4）', () {
    final plan = buildMatchPlan(allCards: cards, karafudaPercent: 0, rng: Random(7));
    final slots = plan.slots;
    final all = {for (var i = 0; i < 12; i++) i};
    final enemyRead = ReadItem(slots[1].card, slotIndex: 1); // 敵陣
    final selfRead = ReadItem(slots[8].card, slotIndex: 8); // 自陣
    final kara = ReadItem(cards.firstWhere((c) => !slots.any((s) => s.card.id == c.id)));

    MatchOutcome? j(ReadItem r, MatchAction a, [Set<int>? occ]) =>
        judgeMatch(read: r, action: a, slots: slots, occupied: occ ?? all);

    test('正しい札：正解', () {
      expect(j(enemyRead, const TapSlot(1)), MatchOutcome.correct);
      expect(j(selfRead, const TapSlot(8)), MatchOutcome.correct);
    });
    test('同じ陣の別の札：同陣ミス（読みは終わらない）', () {
      expect(j(enemyRead, const TapSlot(4)), MatchOutcome.sameSide);
      expect(j(selfRead, const TapSlot(11)), MatchOutcome.sameSide);
      expect(MatchOutcome.sameSide.endsRead, isFalse);
    });
    test('反対の陣の札：お手つき＋取り逃し', () {
      final o = j(enemyRead, const TapSlot(6))!;
      expect(o, MatchOutcome.oppositeSide);
      expect(o.isOtetsuki && o.isMissed && o.endsRead, isTrue);
    });
    test('場の札で時間切れ・見送り：取り逃し', () {
      expect(j(selfRead, const TimeUpMatch()), MatchOutcome.timeUp);
      expect(j(selfRead, const PressPassMatch()), MatchOutcome.passOnField);
    });
    test('空札：押すとお手つき、見送り・何もしないと見送り成功', () {
      expect(j(kara, const TapSlot(0)), MatchOutcome.karafudaTouched);
      expect(j(kara, const PressPassMatch()), MatchOutcome.passOk);
      expect(j(kara, const TimeUpMatch()), MatchOutcome.waitOk);
      expect(MatchOutcome.waitOk.isPassSuccess, isTrue);
    });
    test('空白の位置を押しても何も起きない（空札でも場の札でも）', () {
      final occ = {...all}..remove(3);
      expect(j(enemyRead, const TapSlot(3), occ), isNull);
      expect(j(kara, const TapSlot(3), occ), isNull);
      expect(j(enemyRead, const TapSlot(99)), isNull);
    });
  });

  group('集計・最終正答率・ランク（U5・U6・U8）', () {
    MatchStats stats({int correct = 0, int ms = 1000, int opposite = 0, int touched = 0, int sameSide = 0}) {
      final s = MatchStats();
      for (var i = 0; i < correct; i++) {
        s.record(MatchOutcome.correct, side: i.isEven ? Side.self : Side.enemy, elapsedMs: ms);
      }
      for (var i = 0; i < opposite; i++) {
        s.record(MatchOutcome.oppositeSide, side: Side.self);
      }
      for (var i = 0; i < touched; i++) {
        s.record(MatchOutcome.karafudaTouched);
      }
      for (var i = 0; i < sameSide; i++) {
        s.record(MatchOutcome.sameSide, side: Side.enemy);
      }
      return s;
    }

    test('12枚 → 100%、11枚 → 92%、10枚 → 83%、9枚 → 75%（四捨五入）', () {
      expect(stats(correct: 12).accuracyPercent, 100);
      expect(stats(correct: 11).accuracyPercent, 92);
      expect(stats(correct: 10).accuracyPercent, 83);
      expect(stats(correct: 9).accuracyPercent, 75);
    });
    test('お手つきは1回につき1枚分を引く（反対の陣・空札とも）。下限は 0%', () {
      expect(stats(correct: 11, touched: 1).accuracyPercent, 83);
      expect(stats(correct: 10, opposite: 1, touched: 1).accuracyPercent, 67);
      expect(stats(correct: 1, touched: 3).accuracyPercent, 0);
    });
    test('同陣ミスは減点しない', () {
      final s = stats(correct: 12, sameSide: 5);
      expect(s.sameSide, 5);
      expect(s.accuracyPercent, 100);
    });
    test('ランク：12枚・1.5秒 → S、12枚・2.0秒 → A、11枚・1.0秒 → B（A にならない）、10枚 → C', () {
      expect(stats(correct: 12, ms: 1500).rank, Rank.S);
      expect(stats(correct: 12, ms: 1501).rank, Rank.A);
      expect(stats(correct: 12, ms: 2000).rank, Rank.A);
      expect(stats(correct: 12, ms: 2001).rank, Rank.B);
      expect(stats(correct: 11, ms: 1000).rank, Rank.B);
      expect(stats(correct: 11, ms: 2500).rank, Rank.B);
      expect(stats(correct: 11, ms: 2501).rank, Rank.C);
      expect(stats(correct: 10, ms: 3500).rank, Rank.C);
      expect(stats(correct: 10, ms: 3501).rank, Rank.D);
      expect(stats(correct: 9, ms: 500).rank, Rank.D);
    });
    test('表示する正答率とランクの判定に使う値が同じ', () {
      final s = stats(correct: 11, touched: 0, ms: 1200);
      expect(calcRank(s.accuracyPercent, s.avgTakeMs, mode: PracticeMode.match), s.rank);
    });
    test('正解0枚：平均なし → D', () {
      final s = stats(correct: 0);
      expect(s.avgTakeMs, isNull);
      expect(s.rank, Rank.D);
    });
    test('陣別の取得数・平均', () {
      final s = MatchStats()
        ..record(MatchOutcome.correct, side: Side.self, elapsedMs: 1000)
        ..record(MatchOutcome.correct, side: Side.enemy, elapsedMs: 3000)
        ..record(MatchOutcome.timeUp, side: Side.enemy);
      expect(s.takenOn(Side.self), 1);
      expect(s.takenOn(Side.enemy), 1);
      expect(s.missedOn(Side.enemy), 1);
      expect(s.avgTakeMs, 2000);
      expect(s.avgTakeMsOn(Side.enemy), 3000);
      expect(s.countsByName()['selfTaken'], 1);
    });
    test('実践練習の基準は反応練習と別のリストを参照する', () {
      expect(RankPolicy.rulesFor(PracticeMode.match), same(RankPolicy.matchRules));
      expect(RankPolicy.rulesFor(PracticeMode.reaction), same(RankPolicy.rules));
    });
  });
}
