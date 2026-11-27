// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tokkun_kyogikaruta/app.dart';
import 'package:tokkun_kyogikaruta/providers/settings_provider.dart';

void main() {
  testWidgets('app smoke test', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const App(),
    ));
    // 初期画面の「スタート」ボタンが見えることを確認
    expect(find.text('スタート'), findsOneWidget);
  });
}
