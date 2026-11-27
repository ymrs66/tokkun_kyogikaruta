// test/domain/judge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/domain/judge.dart';
import 'package:tokkun_kyogikaruta/domain/verdict.dart';

void main() {
  const current = 15;

  Verdict j(bool kara, PlayerAction a,
          [KarafudaTimeoutPolicy p = KarafudaTimeoutPolicy.noAnswer]) =>
      judgeNormal(
          isKarafuda: kara, action: a, currentCardId: current, timeoutPolicy: p);

  group('場にある札（取り札）', () {
    test('J1 正しい札 → 正解', () {
      expect(j(false, const TapCard(current)), Verdict.correct);
    });
    test('J2 別の札 → 不正解', () {
      expect(j(false, const TapCard(16)), Verdict.wrong);
    });
    test('J3 見送り → 見送りミス', () {
      expect(j(false, const PressPass()), Verdict.wrongPass);
    });
    test('J4 時間切れ → 取り逃し（方式に関係なく）', () {
      expect(j(false, const TimeUp()), Verdict.missed);
      expect(j(false, const TimeUp(), KarafudaTimeoutPolicy.passOk),
          Verdict.missed);
    });
  });

  group('空札', () {
    test('J5 見送り → 見送り成功', () {
      expect(j(true, const PressPass()), Verdict.passOk);
    });
    test('J6 札を押す → お手つき（読まれた札と同じ ID でも）', () {
      expect(j(true, const TapCard(16)), Verdict.fault);
      expect(j(true, const TapCard(current)), Verdict.fault);
    });
    test('J7 時間切れ → 通常練習は未回答・不正解', () {
      expect(j(true, const TimeUp()), Verdict.noAnswer);
      expect(Verdict.noAnswer.isSuccess, isFalse);
    });
    test('J7 実践モード用の方式なら時間切れも見送り成功', () {
      expect(j(true, const TimeUp(), KarafudaTimeoutPolicy.passOk),
          Verdict.passOk);
    });
  });

  test('正答として数えるのは正解と見送り成功だけ', () {
    expect(Verdict.values.where((v) => v.isSuccess).toSet(),
        {Verdict.correct, Verdict.passOk});
  });
}
