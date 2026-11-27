// test/widgets/ad_privacy_ui_test.dart
//
// 設定画面の「広告のプライバシー設定」の導線と、プライバシーポリシーのリンク。
// UMP はフェイク（モック）。実際のフォームは実機で確認する（報告書 110）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tokkun_kyogikaruta/app.dart';
import 'package:tokkun_kyogikaruta/providers/settings_provider.dart';
import 'package:tokkun_kyogikaruta/screens/privacy_screen.dart';
import 'package:tokkun_kyogikaruta/screens/settings_screen.dart';
import 'package:tokkun_kyogikaruta/services/ad_consent.dart';
import 'package:tokkun_kyogikaruta/services/ad_service.dart';

import '../services/ad_consent_test.dart' show FakeConsentPlatform;

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final p = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(p)],
    child: MaterialApp.router(
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => screen),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late AdConsentController original;
  late FakeConsentPlatform platform;

  setUp(() {
    original = AdService.consent;
    platform = FakeConsentPlatform();
    AdService.consent = AdConsentController(platform: platform, initializeAds: () async {});
  });
  tearDown(() => AdService.consent = original);

  group('設定画面：広告のプライバシー設定', () {
    testWidgets('UMP が求めない（日本の通常の利用者など）：表示しない', (tester) async {
      await AdService.consent.gather();
      await pumpScreen(tester, const SettingsScreen());
      expect(find.text('広告のプライバシー設定'), findsNothing);
      expect(find.text('反応練習'), findsOneWidget);
    });

    testWidgets('UMP が求める：表示し、押すとプライバシー オプションのフォームを開く', (tester) async {
      platform.privacyRequired = true;
      await pumpScreen(tester, const SettingsScreen());
      expect(find.text('広告のプライバシー設定'), findsNothing, reason: '確認前は出さない');

      await tester.runAsync(() => AdService.consent.gather());
      await tester.pumpAndSettle();
      expect(find.text('広告のプライバシー設定'), findsOneWidget);

      await tester.tap(find.text('広告のプライバシー設定'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(platform.calls, contains('privacyForm'));
    });

    testWidgets('広告リクエスト不可でも、プライバシー設定から選択を変更できる', (tester) async {
      platform
        ..privacyRequired = true
        ..canRequest = false;
      await AdService.consent.gather();
      await pumpScreen(tester, const SettingsScreen());
      expect(AdService.consent.canRequestAds, isFalse);
      expect(find.text('広告のプライバシー設定'), findsOneWidget);
    });
  });

  group('ホーム：同意フォームの表示中は練習を始めない', () {
    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      appRouter.go('/');
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(p)],
        child: const App(),
      ));
      await tester.pumpAndSettle();
    }

    for (final label in ['反応練習', '実践練習']) {
      testWidgets('$label：フォームの表示中は押しても始まらず、閉じた後は始められる', (tester) async {
        await pumpHome(tester);
        AdService.consent.formInProgress.value = true;
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/');

        AdService.consent.formInProgress.value = false;
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(appRouter.routerDelegate.currentConfiguration.uri.path, isNot('/'));
        appRouter.go('/');
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5)); // 画面遷移で始まったタイマーを終わらせる
      });
    }

    testWidgets('waitUntilHome：ホームならすぐ終わり、他の画面ならホームに戻るまで待つ', (tester) async {
      await pumpHome(tester);
      await tester.runAsync(() => waitUntilHome());

      appRouter.go('/settings');
      await tester.pumpAndSettle();
      var done = false;
      final f = waitUntilHome().then((_) => done = true);
      await tester.pump();
      expect(done, isFalse);
      appRouter.go('/');
      await tester.pumpAndSettle();
      await f;
      expect(done, isTrue);
    });
  });

  group('プライバシーポリシーのリンク', () {
    test('新しい URL（日本語・英語、Android・iOS 共通）', () {
      expect(privacyPolicyUrl, 'https://www.ymr-system.jp/karuta/privacy.html');
      expect(privacyPolicyUrl, isNot(contains('flycricket')));
    });

    testWidgets('「ブラウザで開く」で新しい URL を開く', (tester) async {
      final opened = <Uri>[];
      await pumpScreen(tester, PrivacyScreen(openUrl: (u) async {
        opened.add(u);
        return true;
      }));
      await tester.tap(find.text('ブラウザで開く'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse(privacyPolicyUrl)]);
      expect(find.textContaining('ブラウザを開けませんでした'), findsNothing);
    });

    testWidgets('開けない（false）：メッセージと URL を表示', (tester) async {
      await pumpScreen(tester, PrivacyScreen(openUrl: (_) async => false));
      await tester.tap(find.text('ブラウザで開く'));
      await tester.pump();
      expect(find.textContaining('ブラウザを開けませんでした'), findsOneWidget);
      expect(find.textContaining(privacyPolicyUrl), findsOneWidget);
    });

    testWidgets('開けない（例外）：落ちずにメッセージを表示', (tester) async {
      await pumpScreen(tester, PrivacyScreen(openUrl: (_) async => throw Exception('no browser')));
      await tester.tap(find.text('ブラウザで開く'));
      await tester.pump();
      expect(find.textContaining('ブラウザを開けませんでした'), findsOneWidget);
    });
  });
}
