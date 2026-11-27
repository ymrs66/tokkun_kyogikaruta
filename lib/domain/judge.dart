// lib/domain/judge.dart
import 'verdict.dart';

/// 反応練習（6枚の場）の判定。純粋関数。
///
/// - [isKarafuda]：読まれた札が場にない（空札）か
/// - [currentCardId]：読まれた札の ID
/// - [timeoutPolicy]：空札で時間切れになったときの扱い
///   （反応練習は [KarafudaTimeoutPolicy.noAnswer]）
///
/// 実践練習（陣の区別・同陣ミス）は Phase 4 で別の関数として追加する。
Verdict judgeNormal({
  required bool isKarafuda,
  required PlayerAction action,
  required int currentCardId,
  KarafudaTimeoutPolicy timeoutPolicy = KarafudaTimeoutPolicy.noAnswer,
}) {
  if (!isKarafuda) {
    return switch (action) {
      TapCard(:final cardId) =>
        cardId == currentCardId ? Verdict.correct : Verdict.wrong,
      PressPass() => Verdict.wrongPass,
      TimeUp() => Verdict.missed,
    };
  }
  return switch (action) {
    TapCard() => Verdict.fault,
    PressPass() => Verdict.passOk,
    TimeUp() => timeoutPolicy == KarafudaTimeoutPolicy.passOk
        ? Verdict.passOk
        : Verdict.noAnswer,
  };
}
