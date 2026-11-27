// lib/models/game_config.dart
import 'package:flutter/foundation.dart';

import '../domain/question_plan.dart';
import '../domain/verdict.dart';
import 'app_settings.dart';

/// 練習開始時に固定する設定（練習中に設定を変えても、その練習には影響しない）。
@immutable
class GameConfig {
  const GameConfig({
    this.totalQuestions = 10,
    this.karafudaPercent = 0,
    this.otetsukiPenalty = false,
    this.timeLimitMs = 10000,
    this.timeoutPolicy = KarafudaTimeoutPolicy.noAnswer,
  });

  final int totalQuestions;

  /// 空札の割合（0 = 空札なし）
  final int karafudaPercent;
  final bool otetsukiPenalty;

  /// 1問の制限時間（読み上げ開始から）
  final int timeLimitMs;

  /// 空札で時間切れになったときの扱い（反応練習は未回答・不正解）
  final KarafudaTimeoutPolicy timeoutPolicy;

  bool get karafudaEnabled => karafudaPercent > 0;

  /// 設定から作る。
  ///
  /// debug ビルドだけ、起動引数で空札を ON にできる（Phase 3 で設定画面ができるまでの確認用）。
  ///   flutter run --dart-define=DEBUG_KARAFUDA_PERCENT=30 --dart-define=DEBUG_OTETSUKI_PENALTY=true
  /// release・profile では [kDebugMode] が false なので使われない（画面上のデバッグ UI はない）。
  factory GameConfig.fromSettings(AppSettings s) {
    var percent = s.effectiveKarafudaPercent;
    var penalty = s.otetsukiPenalty;
    if (kDebugMode) {
      const debugPercent =
          int.fromEnvironment('DEBUG_KARAFUDA_PERCENT', defaultValue: -1);
      const debugPenalty = String.fromEnvironment('DEBUG_OTETSUKI_PENALTY');
      if (karafudaPercentOptions.contains(debugPercent)) percent = debugPercent;
      if (debugPenalty == 'true') penalty = true;
      if (debugPenalty == 'false') penalty = false;
    }
    return GameConfig(
      karafudaPercent: karafudaPercentOptions.contains(percent) ? percent : 0,
      otetsukiPenalty: percent > 0 && penalty,
    );
  }
}
