// lib/domain/match_judge.dart
//
// 実践練習の判定（純粋関数）。反応練習の judgeNormal・Verdict は変えない。
// 競技かるたの正式ルールではなく、手軽に練習するための簡易ルール。
import 'match_plan.dart';

/// 実践練習の操作
sealed class MatchAction {
  const MatchAction();
}

/// 札の位置を押した（空白の位置は判定しない：呼び出し側で除く）
class TapSlot extends MatchAction {
  const TapSlot(this.slotIndex);
  final int slotIndex;
}

class PressPassMatch extends MatchAction {
  const PressPassMatch();
}

class TimeUpMatch extends MatchAction {
  const TimeUpMatch();
}

/// 1回の操作の判定結果
enum MatchOutcome {
  /// 場の札：正しい札（取った）
  correct,

  /// 場の札：同じ陣の別の札（減点なし・受付を続ける）
  sameSide,

  /// 場の札：反対の陣の札（お手つき＋取り逃し）
  oppositeSide,

  /// 場の札：時間切れ（取り逃し）
  timeUp,

  /// 場の札：見送り（取り逃し）
  passOnField,

  /// 空札：札を押した（お手つき）
  karafudaTouched,

  /// 空札：見送りを押した（見送り成功）
  passOk,

  /// 空札：何もせず時間切れ（見送り成功）
  waitOk,
}

extension MatchOutcomeX on MatchOutcome {
  /// その読みを終える判定か（同陣ミスだけは受付を続ける）
  bool get endsRead => this != MatchOutcome.sameSide;

  /// お手つきとして数えるか
  bool get isOtetsuki =>
      this == MatchOutcome.oppositeSide || this == MatchOutcome.karafudaTouched;

  /// 場の札を取り逃したか
  bool get isMissed =>
      this == MatchOutcome.oppositeSide ||
      this == MatchOutcome.timeUp ||
      this == MatchOutcome.passOnField;

  /// 見送り成功か
  bool get isPassSuccess => this == MatchOutcome.passOk || this == MatchOutcome.waitOk;
}

/// 判定する。[occupied] はまだ札が残っている位置（空白は含まない）。
/// 空白の位置・範囲外を押したときは null（何も起きない）。
MatchOutcome? judgeMatch({
  required ReadItem read,
  required MatchAction action,
  required List<MatchSlot> slots,
  required Set<int> occupied,
}) {
  if (action is TapSlot && !occupied.contains(action.slotIndex)) return null;
  final target = read.slotIndex;
  if (target == null) {
    return switch (action) {
      TapSlot() => MatchOutcome.karafudaTouched,
      PressPassMatch() => MatchOutcome.passOk,
      TimeUpMatch() => MatchOutcome.waitOk,
    };
  }
  return switch (action) {
    TapSlot(:final slotIndex) => slotIndex == target
        ? MatchOutcome.correct
        : (slots[slotIndex].side == slots[target].side
            ? MatchOutcome.sameSide
            : MatchOutcome.oppositeSide),
    PressPassMatch() => MatchOutcome.passOnField,
    TimeUpMatch() => MatchOutcome.timeUp,
  };
}
