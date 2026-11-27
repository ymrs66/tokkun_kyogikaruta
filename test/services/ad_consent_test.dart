// test/services/ad_consent_test.dart
//
// UMP（広告の同意）の流れ。SDK はフェイクに差し替えたモックのテスト。
// 実際の同意フォームの表示は、AdMob の管理画面でメッセージを公開した後に実機で確認する（報告書 105・110）。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:tokkun_kyogikaruta/services/ad_consent.dart';
import 'package:tokkun_kyogikaruta/services/ad_service.dart';

class FakeConsentPlatform implements ConsentPlatform {
  bool updateSucceeds = true;
  bool updateThrows = false;
  bool formRequired = false;
  bool formThrows = false;
  bool canRequest = true;
  bool privacyRequired = false;

  /// プライバシー オプションのフォームを閉じたときに変わる canRequestAds
  bool? canRequestAfterPrivacyForm;

  final List<String> calls = [];
  Completer<bool>? holdUpdate;

  @override
  Future<bool> requestConsentInfoUpdate() async {
    calls.add('update');
    if (holdUpdate != null) return holdUpdate!.future;
    if (updateThrows) throw Exception('offline');
    return updateSucceeds;
  }

  @override
  Future<void> loadAndShowConsentFormIfRequired() async {
    calls.add('formIfRequired');
    if (formThrows) throw Exception('form failed');
    if (formRequired) calls.add('formShown');
  }

  @override
  Future<bool> canRequestAds() async {
    calls.add('canRequestAds');
    return canRequest;
  }

  @override
  Future<bool> isPrivacyOptionsRequired() async => privacyRequired;

  @override
  Future<void> showPrivacyOptionsForm() async {
    calls.add('privacyForm');
    if (canRequestAfterPrivacyForm != null) canRequest = canRequestAfterPrivacyForm!;
  }
}

void main() {
  late FakeConsentPlatform platform;
  late int initCount;
  late AdConsentController c;

  setUp(() {
    platform = FakeConsentPlatform();
    initCount = 0;
    c = AdConsentController(
      platform: platform,
      initializeAds: () async => initCount++,
    );
  });

  test('起動直後（確認前）は広告をリクエストしない', () {
    expect(c.canRequestAds, isFalse);
    expect(c.state.value.privacyOptionsRequired, isFalse);
    expect(initCount, 0);
  });

  test('広告リクエスト可能：更新 → フォーム（必要なら）→ 可否確認 → SDK 初期化の順', () async {
    await c.gather();
    expect(platform.calls, ['update', 'formIfRequired', 'canRequestAds']);
    expect(c.canRequestAds, isTrue);
    expect(initCount, 1);
  });

  test('同意フォームが必要な地域：フォームを表示してから可否を確認', () async {
    platform.formRequired = true;
    await c.gather();
    expect(platform.calls, ['update', 'formIfRequired', 'formShown', 'canRequestAds']);
    expect(c.canRequestAds, isTrue);
  });

  test('広告リクエスト不可（同意なし）：SDK を初期化せず、広告を出さない', () async {
    platform.canRequest = false;
    await c.gather();
    expect(c.canRequestAds, isFalse);
    expect(initCount, 0);
  });

  test('同意情報の取得失敗（オフライン）：フォームは出さず、前回の同意状態で判断する', () async {
    platform.updateSucceeds = false;
    await c.gather();
    expect(platform.calls, ['update', 'canRequestAds']);
    expect(c.canRequestAds, isTrue, reason: '前回の起動で許可されていれば広告を読み込める');

    platform.calls.clear();
    platform.canRequest = false;
    final c2 = AdConsentController(platform: platform, initializeAds: () async => initCount++);
    await c2.gather();
    expect(c2.canRequestAds, isFalse, reason: '前回の同意がなければ広告を出さない');
  });

  test('例外（チャンネルの失敗など）でも止まらず、可否を確認する', () async {
    platform.updateThrows = true;
    await c.gather();
    expect(c.canRequestAds, isTrue);

    platform.updateThrows = false;
    platform.formThrows = true;
    await c.gather();
    expect(c.canRequestAds, isTrue);
  });

  test('SDK の初期化に失敗したら広告を出さず、次の確認で再試行する', () async {
    var fail = true;
    final c3 = AdConsentController(
      platform: platform,
      initializeAds: () async {
        initCount++;
        if (fail) throw Exception('init failed');
      },
    );
    await c3.gather();
    expect(c3.canRequestAds, isFalse);
    fail = false;
    await c3.gather();
    expect(c3.canRequestAds, isTrue);
    expect(initCount, 2);
  });

  test('初期化の重複防止：同時に呼んでも更新は1回、何度確認しても初期化は1回', () async {
    platform.holdUpdate = Completer<bool>();
    final a = c.gather();
    final b = c.gather();
    expect(platform.calls.where((x) => x == 'update').length, 1);
    platform.holdUpdate!.complete(true);
    await Future.wait([a, b]);
    platform.holdUpdate = null;
    await c.gather();
    await c.gather();
    expect(initCount, 1);
  });

  test('プライバシー設定の導線：必要なときだけ表示フラグが立つ', () async {
    await c.gather();
    expect(c.state.value.privacyOptionsRequired, isFalse);
    platform.privacyRequired = true;
    await c.gather();
    expect(c.state.value.privacyOptionsRequired, isTrue);
  });

  test('同意状態の変更：プライバシー設定を閉じると generation が増え、不許可になれば広告を止める', () async {
    platform.privacyRequired = true;
    await c.gather();
    final g0 = c.state.value.generation;

    await c.showPrivacyOptions();
    expect(c.state.value.generation, g0 + 1, reason: '読み込み済みの広告を作り直す合図');
    expect(c.canRequestAds, isTrue);

    platform.canRequestAfterPrivacyForm = false;
    await c.showPrivacyOptions();
    expect(c.canRequestAds, isFalse);
    expect(c.state.value.generation, g0 + 2);
    expect(initCount, 1);
  });

  group('UMP のデバッグ設定', () {
    test('release では指定があっても常に無効（正式版に混入しない）', () {
      expect(
        umpDebugSettingsFor(isRelease: true, geography: 'eea', testDeviceIds: 'ABC'),
        isNull,
      );
    });
    test('debug/profile で指定がなければ無効', () {
      expect(umpDebugSettingsFor(isRelease: false, geography: '', testDeviceIds: ''), isNull);
    });
    test('debug/profile で地域・テスト端末を指定できる', () {
      final s = umpDebugSettingsFor(isRelease: false, geography: 'EEA', testDeviceIds: ' A , B ,');
      expect(s?.debugGeography, DebugGeography.debugGeographyEea);
      expect(s?.testIdentifiers, ['A', 'B']);
      expect(
        umpDebugSettingsFor(isRelease: false, geography: 'us_state', testDeviceIds: '')
            ?.debugGeography,
        DebugGeography.debugGeographyRegulatedUsState,
      );
    });
    test('テスト実行時（環境変数なし）は無効', () {
      expect(umpDebugSettingsFromEnvironment(), isNull);
    });
  });

  test('広告の内容は一般向け（G）までに制限する。年齢の扱いは未指定（未確定のため）', () {
    final rc = AdService.requestConfiguration;
    expect(rc.maxAdContentRating, MaxAdContentRating.g);
    expect(rc.ageRestrictedTreatment, isNull);
    expect(rc.testDeviceIds, isNull, reason: '指定がなければテスト端末なし');
    final tf = AdService.requestConfigurationFor(testDeviceIds: ' H1 ,H2,');
    expect(tf.testDeviceIds, ['H1', 'H2']);
    expect(tf.maxAdContentRating, MaxAdContentRating.g);
  });

  test('テスト実行時は同意確認・広告の読み込みを行わない', () async {
    await AdService.start();
    expect(AdService.consent.canRequestAds, isFalse);
    expect(AdService.consent.adsInitialized, isFalse);
  });
}
