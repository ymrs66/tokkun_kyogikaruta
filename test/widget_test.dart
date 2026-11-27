import 'package:flutter/material.dart';
// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tokkun_kyogikaruta/app.dart';
import 'package:tokkun_kyogikaruta/providers/settings_provider.dart';

void main() {
  testWidgets('app smoke test：ホームに反応練習と説明文がある', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const App(),
    ));
    expect(find.text('反応練習'), findsOneWidget);
    expect(find.text('札の認識力・判断力・反応速度を鍛える'), findsOneWidget);
  });

  // Phase 4.5：textScaleFactor → textScaler に移行しても、文字の拡大は 1.0〜1.3 倍に収める
  for (final (device, expected) in [(0.8, 1.0), (1.0, 1.0), (1.2, 1.2), (2.0, 1.3)]) {
    testWidgets('端末の文字サイズ $device 倍 → アプリでは $expected 倍', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = device;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const App(),
      ));
      final ctx = tester.element(find.text('反応練習'));
      expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(expected * 10, 0.001));
    });
  }
}

