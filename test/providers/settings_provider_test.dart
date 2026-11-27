// test/providers/settings_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tokkun_kyogikaruta/models/app_settings.dart';
import 'package:tokkun_kyogikaruta/models/game_config.dart';
import 'package:tokkun_kyogikaruta/providers/settings_provider.dart';

Future<ProviderContainer> containerWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final p = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
}

void main() {
  test('キーがない（既存ユーザー）→ 初期値：空札なし・30%・ペナルティなし・音あり・文字あり', () async {
    final c = await containerWith({});
    expect(c.read(settingsProvider), const AppSettings());
    final cfg = GameConfig.fromSettings(c.read(settingsProvider));
    expect(cfg.karafudaPercent, 0);
    expect(cfg.otetsukiPenalty, isFalse);
    expect(cfg.totalQuestions, 10);
    expect(cfg.timeLimitMs, 10000);
  });

  test('保存した値は作り直しても残る（再起動の代わり）', () async {
    final c = await containerWith({});
    await c.read(settingsProvider.notifier).setSoundOn(false);
    await c.read(settingsProvider.notifier).setTextFlowOn(false);
    final p = c.read(sharedPrefsProvider);
    final c2 = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
    expect(c2.read(soundOnProvider), isFalse);
    expect(c2.read(textFlowOnProvider), isFalse);
  });

  test('範囲外・型違いの値は初期値に戻る', () async {
    final c = await containerWith({
      SettingsKeys.karafudaPercent: 70,
      SettingsKeys.soundOn: 'yes',
    });
    final s = c.read(settingsProvider);
    expect(s.karafudaPercent, 30);
    expect(s.soundOn, isTrue);
  });

  test('空札 OFF ならペナルティ設定は練習に反映しない', () async {
    final c = await containerWith({SettingsKeys.otetsukiPenalty: true});
    expect(GameConfig.fromSettings(c.read(settingsProvider)).otetsukiPenalty,
        isFalse);
  });

  test('空札 ON（50%）・ペナルティ ON は練習の設定に反映する', () async {
    final c = await containerWith({
      SettingsKeys.karafudaEnabled: true,
      SettingsKeys.karafudaPercent: 50,
      SettingsKeys.otetsukiPenalty: true,
    });
    final cfg = GameConfig.fromSettings(c.read(settingsProvider));
    expect(cfg.karafudaPercent, 50);
    expect(cfg.otetsukiPenalty, isTrue);
  });

  group('実践練習の開始条件（Phase 4）', () {
    test('初期値：暗記 1分・空札 30%', () async {
      final c = await containerWith({});
      expect(c.read(settingsProvider).matchMemorizeSec, 60);
      expect(c.read(settingsProvider).matchKarafudaPercent, 30);
    });
    test('選んだ値は保存され、次回の初期値になる。範囲外は初期値', () async {
      final c = await containerWith({});
      await c.read(settingsProvider.notifier).setMatchMemorizeSec(180);
      await c.read(settingsProvider.notifier).setMatchKarafudaPercent(0);
      await c.read(settingsProvider.notifier).setMatchMemorizeSec(300); // 選択肢にない
      final p = c.read(sharedPrefsProvider);
      final c2 = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
      expect(c2.read(settingsProvider).matchMemorizeSec, 180);
      expect(c2.read(settingsProvider).matchKarafudaPercent, 0);
      final c3 = await containerWith({
        SettingsKeys.matchMemorizeSec: 15,
        SettingsKeys.matchKarafudaPercent: 20,
      });
      expect(c3.read(settingsProvider).matchMemorizeSec, 60);
      expect(c3.read(settingsProvider).matchKarafudaPercent, 30);
    });
    test('設定を初期値に戻すと実践練習の条件も戻る', () async {
      final c = await containerWith({
        SettingsKeys.matchMemorizeSec: 30,
        SettingsKeys.matchKarafudaPercent: 50,
        'record.v2.match.last': '{}',
      });
      await c.read(settingsProvider.notifier).resetToDefaults();
      final p = c.read(sharedPrefsProvider);
      expect(p.containsKey(SettingsKeys.matchMemorizeSec), isFalse);
      expect(p.containsKey(SettingsKeys.matchKarafudaPercent), isFalse);
      expect(p.containsKey('record.v2.match.last'), isTrue);
      expect(c.read(settingsProvider).matchMemorizeSec, 60);
    });
  });
}
