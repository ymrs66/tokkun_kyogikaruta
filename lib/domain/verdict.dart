// lib/domain/verdict.dart
//
// 判定の種類とプレイヤーの操作（Flutter に依存しない）。

/// 1問の判定結果。
enum Verdict {
  /// 場にある札：正しい札を押した
  correct,

  /// 場にある札：別の札を押した
  wrong,

  /// 場にある札：見送りを押した（見送りミス）
  wrongPass,

  /// 場にある札：時間切れ（取り逃し）
  missed,

  /// 空札：見送りを押した（見送り成功）
  passOk,

  /// 空札：札を押した（お手つき）
  fault,

  /// 空札：時間切れ（反応練習では未回答・不正解）
  noAnswer,
}

extension VerdictX on Verdict {
  /// 正答として数えるか（正解・見送り成功）
  bool get isSuccess => this == Verdict.correct || this == Verdict.passOk;
}

/// 空札で何もしないまま時間切れになったときの扱い。
/// 反応練習と実践練習（Phase 4）で判定処理を共通にするための引数。
enum KarafudaTimeoutPolicy {
  /// 未回答・不正解（反応練習：見送りボタンで明示する練習）
  noAnswer,

  /// 見送り成功（実践練習の候補：触らないことが正しい）
  passOk,
}

/// プレイヤーの操作。
sealed class PlayerAction {
  const PlayerAction();
}

/// 札を押した
class TapCard extends PlayerAction {
  const TapCard(this.cardId);
  final int cardId;
}

/// 見送りを押した
class PressPass extends PlayerAction {
  const PressPass();
}

/// 制限時間が過ぎた
class TimeUp extends PlayerAction {
  const TimeUp();
}
