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
            isRelease: false, testId: AdService.testBannerId, releaseId: prod),
        AdService.testBannerId,
      );
    });
    test('release では渡された本番IDを使う', () {
      expect(
        AdService.resolveUnitId(
            isRelease: true, testId: AdService.testBannerId, releaseId: prod),
        prod,
      );
    });
    test('release で本番IDが未設定なら広告を読み込まない（null）', () {
      expect(
        AdService.resolveUnitId(
            isRelease: true, testId: AdService.testBannerId, releaseId: ''),
        isNull,
      );
    });
  });

  test('テスト実行時（非release）はテストIDになる', () {
    expect(kReleaseMode, isFalse);
    expect(AdService.bannerId, AdService.testBannerId);
    expect(AdService.interstitialId, AdService.testInterstitialId);
  });
}
