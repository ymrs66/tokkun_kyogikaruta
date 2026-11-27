// lib/models/app_settings.dart
import 'package:flutter/foundation.dart';

import '../domain/question_plan.dart';

/// アプリの設定（端末に保存する）。初期値は既存ユーザーが従来どおり練習できる値。
@immutable
class AppSettings {
  const AppSettings({
    this.karafudaEnabled = false,
    this.karafudaPercent = 30,
    this.otetsukiPenalty = false,
    this.soundOn = true,
    this.textFlowOn = true,
  });

  /// 空札あり（初期値 OFF）
  final bool karafudaEnabled;

  /// 空札の割合（20／30／50。空札ありのときだけ有効）
  final int karafudaPercent;

  /// お手つきペナルティ（初期値 OFF）
  final bool otetsukiPenalty;

  /// 読み上げ音声
  final bool soundOn;

  /// 上の句の文字表示
  final bool textFlowOn;

  /// 実際に使う空札の割合（空札なしなら 0）
  int get effectiveKarafudaPercent => karafudaEnabled ? karafudaPercent : 0;

  AppSettings copyWith({
    bool? karafudaEnabled,
    int? karafudaPercent,
    bool? otetsukiPenalty,
    bool? soundOn,
    bool? textFlowOn,
  }) =>
      AppSettings(
        karafudaEnabled: karafudaEnabled ?? this.karafudaEnabled,
        karafudaPercent: karafudaPercent ?? this.karafudaPercent,
        otetsukiPenalty: otetsukiPenalty ?? this.otetsukiPenalty,
        soundOn: soundOn ?? this.soundOn,
        textFlowOn: textFlowOn ?? this.textFlowOn,
      );

  /// 空札の割合として正しい値か（0 は「空札なし」なので設定値としては使わない）
  static bool isValidPercent(int p) => p != 0 && karafudaPercentOptions.contains(p);

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.karafudaEnabled == karafudaEnabled &&
      other.karafudaPercent == karafudaPercent &&
      other.otetsukiPenalty == otetsukiPenalty &&
      other.soundOn == soundOn &&
      other.textFlowOn == textFlowOn;

  @override
  int get hashCode => Object.hash(
      karafudaEnabled, karafudaPercent, otetsukiPenalty, soundOn, textFlowOn);
}
