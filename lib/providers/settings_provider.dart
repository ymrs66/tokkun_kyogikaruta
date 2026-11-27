// lib/providers/settings_provider.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/match_plan.dart';
import '../models/app_settings.dart';

/// 起動時に読み込んだ SharedPreferences（main.dart で override する）
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider を override してください'),
);

/// 設定の保存キー（接頭辞＋版番号）
class SettingsKeys {
  SettingsKeys._();
  static const prefix = 'settings.v1.';
  static const karafudaEnabled = '${prefix}karafudaEnabled';
  static const karafudaPercent = '${prefix}karafudaPercent';
  static const otetsukiPenalty = '${prefix}otetsukiPenalty';
  static const soundOn = '${prefix}soundOn';
  static const textFlowOn = '${prefix}textFlowOn';

  /// 実践練習の開始条件（前回の値を次回の初期値にする）
  static const matchMemorizeSec = '${prefix}match.memorizeSec';
  static const matchKarafudaPercent = '${prefix}match.karafudaPercent';
  static const all = [
    karafudaEnabled,
    karafudaPercent,
    otetsukiPenalty,
    soundOn,
    textFlowOn,
    matchMemorizeSec,
    matchKarafudaPercent,
  ];
}

class SettingsNotifier extends Notifier<AppSettings> {
  late SharedPreferences _p;

  @override
  AppSettings build() {
    _p = ref.watch(sharedPrefsProvider);
    return load(_p);
  }

  /// 保存値を読む。キーがない・型が違う・範囲外なら初期値。
  static AppSettings load(SharedPreferences p) {
    const d = AppSettings();
    bool b(String k, bool def) {
      final v = p.get(k);
      return v is bool ? v : def;
    }

    final rawPercent = p.get(SettingsKeys.karafudaPercent);
    final percent = rawPercent is int && AppSettings.isValidPercent(rawPercent)
        ? rawPercent
        : d.karafudaPercent;
    final rawMem = p.get(SettingsKeys.matchMemorizeSec);
    final rawMatchKara = p.get(SettingsKeys.matchKarafudaPercent);
    return AppSettings(
      matchMemorizeSec: rawMem is int && matchMemorizeSecOptions.contains(rawMem)
          ? rawMem
          : d.matchMemorizeSec,
      matchKarafudaPercent:
          rawMatchKara is int && matchKarafudaPercentOptions.contains(rawMatchKara)
              ? rawMatchKara
              : d.matchKarafudaPercent,
      karafudaEnabled: b(SettingsKeys.karafudaEnabled, d.karafudaEnabled),
      karafudaPercent: percent,
      otetsukiPenalty: b(SettingsKeys.otetsukiPenalty, d.otetsukiPenalty),
      soundOn: b(SettingsKeys.soundOn, d.soundOn),
      textFlowOn: b(SettingsKeys.textFlowOn, d.textFlowOn),
    );
  }

  Future<void> setSoundOn(bool v) async {
    state = state.copyWith(soundOn: v);
    await _p.setBool(SettingsKeys.soundOn, v);
  }

  Future<void> setTextFlowOn(bool v) async {
    state = state.copyWith(textFlowOn: v);
    await _p.setBool(SettingsKeys.textFlowOn, v);
  }

  Future<void> setKarafudaEnabled(bool v) async {
    state = state.copyWith(karafudaEnabled: v);
    await _p.setBool(SettingsKeys.karafudaEnabled, v);
  }

  Future<void> setKarafudaPercent(int v) async {
    if (!AppSettings.isValidPercent(v)) return;
    state = state.copyWith(karafudaPercent: v);
    await _p.setInt(SettingsKeys.karafudaPercent, v);
  }

  Future<void> setOtetsukiPenalty(bool v) async {
    state = state.copyWith(otetsukiPenalty: v);
    await _p.setBool(SettingsKeys.otetsukiPenalty, v);
  }

  Future<void> setMatchMemorizeSec(int v) async {
    if (!matchMemorizeSecOptions.contains(v)) return;
    state = state.copyWith(matchMemorizeSec: v);
    await _p.setInt(SettingsKeys.matchMemorizeSec, v);
  }

  Future<void> setMatchKarafudaPercent(int v) async {
    if (!matchKarafudaPercentOptions.contains(v)) return;
    state = state.copyWith(matchKarafudaPercent: v);
    await _p.setInt(SettingsKeys.matchKarafudaPercent, v);
  }

  /// 設定を初期値に戻す（settings.v1.* だけを消す。成績・ギャラリーには触れない）
  Future<void> resetToDefaults() async {
    for (final k in SettingsKeys.all) {
      await _p.remove(k);
    }
    state = const AppSettings();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// 既存コード互換：読み上げ音声の ON/OFF（設定から派生。変更は settingsProvider で行う）
final soundOnProvider =
    Provider<bool>((ref) => ref.watch(settingsProvider).soundOn);

/// 既存コード互換：上の句の文字表示の ON/OFF
final textFlowOnProvider =
    Provider<bool>((ref) => ref.watch(settingsProvider).textFlowOn);
