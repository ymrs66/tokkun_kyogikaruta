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
}
