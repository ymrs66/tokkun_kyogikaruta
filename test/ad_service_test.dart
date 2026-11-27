// test/ad_service_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokkun_kyogikaruta/services/ad_service.dart';

void main() {
  const prod = 'ca-app-pub-1111111111111111/2222222222';

  group('AdService.resolveUnitId', () {
    test('debug/profile では本番IDが渡されていてもテストIDを使う', () {
      expect(
        AdService.resolveUnitId(
            isRelease: false, testId: AdService.testBannerIdAndroid, releaseId: prod),
        AdService.testBannerIdAndroid,
      );
    });
    test('release では渡された本番IDを使う', () {
      expect(
        AdService.resolveUnitId(
            isRelease: true, testId: AdService.testBannerIdAndroid, releaseId: prod),
        prod,
      );
    });
    test('release で本番IDが未設定なら広告を読み込まない（null）', () {
      expect(
        AdService.resolveUnitId(
            isRelease: true, testId: AdService.testBannerIdAndroid, releaseId: ''),
        isNull,
      );
    });
  });

  group('AdService.unitIdFor（OS 別の ID）', () {
    test('debug/profile の Android は Android のテストID', () {
      expect(AdService.unitIdFor(ios: false, isRelease: false, banner: true),
          AdService.testBannerIdAndroid);
      expect(AdService.unitIdFor(ios: false, isRelease: false, banner: false),
          AdService.testInterstitialIdAndroid);
    });
    test('debug/profile の iOS は iOS のテストID', () {
      expect(AdService.unitIdFor(ios: true, isRelease: false, banner: true),
          AdService.testBannerIdIos);
      expect(AdService.unitIdFor(ios: true, isRelease: false, banner: false),
          AdService.testInterstitialIdIos);
    });
    test('テストIDは OS ごとに異なり、すべて Google のテスト用パブリッシャー', () {
      final ids = {
        AdService.testBannerIdAndroid,
        AdService.testInterstitialIdAndroid,
        AdService.testBannerIdIos,
        AdService.testInterstitialIdIos,
      };
      expect(ids.length, 4);
      for (final id in ids) {
        expect(id, startsWith('ca-app-pub-3940256099942544/'));
      }
    });
    test('release で本番IDを渡していなければ両 OS とも null（テストIDに戻らない）', () {
      for (final ios in [false, true]) {
        for (final banner in [false, true]) {
          expect(AdService.unitIdFor(ios: ios, isRelease: true, banner: banner),
              isNull);
        }
      }
    });
  });

  test('テスト実行時（非release）はテストIDになり、広告は読み込まない', () {
    expect(kReleaseMode, isFalse);
    expect(AdService.bannerId, AdService.testBannerIdAndroid);
    expect(AdService.interstitialId, AdService.testInterstitialIdAndroid);
    expect(AdService.isSupportedPlatform, isFalse);
  });
}
