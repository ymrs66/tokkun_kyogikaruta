// test/domain/question_plan_test.dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/data/cards.dart';
import 'package:tokkun_kyogikaruta/domain/field_deck.dart';
import 'package:tokkun_kyogikaruta/domain/question_plan.dart';
import 'package:tokkun_kyogikaruta/models/card_data.dart';

void main() {
  group('空札の問題数', () {
    test('割合 0/20/30/50 → 10問中 0/2/3/5 問（ちょうど）', () {
      for (final (p, k) in [(0, 0), (20, 2), (30, 3), (50, 5)]) {
        for (var seed = 0; seed < 200; seed++) {
          final plan = buildQuestionPlan(
              total: 10, karafudaPercent: p, rng: Random(seed));
          expect(plan.length, 10);
          expect(plan.where((q) => q == QuestionKind.karafuda).length, k,
              reason: 'percent=$p seed=$seed');
        }
      }
    });
    test('選択肢にない割合は空札なし', () {
      expect(karafudaCountFor(percent: 70, total: 10), 0);
      expect(karafudaCountFor(percent: -1, total: 10), 0);
    });
  });

  group('場と山札（FieldDeck）', () {
    test('空札は場にない札・同じ札は二度読まれない（1,000通り）', () {
      for (var seed = 0; seed < 1000; seed++) {
        final rng = Random(seed);
        final plan = buildQuestionPlan(total: 10, karafudaPercent: 50, rng: rng);
        final deck = FieldDeck(allCards: cards, rng: rng);
        final read = <int>{};
        for (var i = 0; i < plan.length; i++) {
          final kind = plan[i];
          final remainingKara =
              plan.skip(i + 1).where((q) => q == QuestionKind.karafuda).length;
          final c = deck.draw(kind)!;
          if (kind == QuestionKind.karafuda) {
            expect(deck.field.any((f) => f.id == c.id), isFalse);
          } else {
            expect(deck.field.any((f) => f.id == c.id), isTrue);
          }
          expect(read.add(c.id), isTrue, reason: 'seed=$seed 重複 ${c.id}');
          deck.retire(c, kind, reserveForKarafuda: remainingKara);
          expect(deck.field.length, 6);
        }
      }
    });

    test('空札の問題では場の6枚が変わらない', () {
      final deck = FieldDeck(allCards: cards, rng: Random(1));
      final before = deck.field.map((c) => c.id).toSet();
      final k = deck.draw(QuestionKind.karafuda)!;
      deck.retire(k, QuestionKind.karafuda, reserveForKarafuda: 0);
      expect(deck.field.map((c) => c.id).toSet(), before);
    });

    test('取り札の問題では読んだ札が場から外れ、1枚補充される', () {
      final deck = FieldDeck(allCards: cards, rng: Random(2));
      final c = deck.draw(QuestionKind.field)!;
      deck.retire(c, QuestionKind.field, reserveForKarafuda: 0);
      expect(deck.field.length, 6);
      expect(deck.field.any((f) => f.id == c.id), isFalse);
      expect(deck.selfCards.length + deck.enemyCards.length, 6);
    });

    test('札が少ないとき、残りの計画を出せるかを正しく判定する', () {
      // 8枚だけ：場6・山札2
      final few = [for (var i = 1; i <= 8; i++) CardData(i, '上$i', '下$i')];
      final deck = FieldDeck(allCards: few, rng: Random(3));
      expect(deck.deckRemaining, 2);
      expect(deck.canServe(remainingField: 6, remainingKarafuda: 2), isTrue);
      expect(deck.canServe(remainingField: 6, remainingKarafuda: 3), isFalse);
      expect(deck.canServe(remainingField: 8, remainingKarafuda: 0), isTrue);
      expect(deck.canServe(remainingField: 9, remainingKarafuda: 0), isFalse);
      // 空札の分を残して補充しない
      final c = deck.draw(QuestionKind.field)!;
      deck.retire(c, QuestionKind.field, reserveForKarafuda: 2);
      expect(deck.field.length, 5);
      expect(deck.deckRemaining, 2);
    });
  });
}
