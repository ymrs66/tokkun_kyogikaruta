// lib/services/ad_service.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 広告ユニットIDの切り替え
///
/// - debug / profile ビルド：常に Google 配布のテストID（本番IDは使わない）
/// - release ビルド：`--dart-define-from-file=admob_release.json` で渡した本番ID
///   （admob_release.json は Git 管理外。手順は README.md「AdMob 本番設定」）
///
/// release で本番IDが渡されていない場合、Android の Gradle 側でビルドを止める
/// （android/app/build.gradle.kts）。万一すり抜けた場合も広告を読み込まない。
class AdService {
  static bool get _androidMobile => Platform.isAndroid && !kIsWeb;

  // Google配布のテストユニットID（Android）
  static const String testBannerId       = 'ca-app-pub-3940256099942544/6300978111';
  static const String testInterstitialId = 'ca-app-pub-3940256099942544/1033173712';

  // 本番ユニットID（Android）：release ビルド時に dart-define で注入
  static const String _releaseBannerId =
      String.fromEnvironment('ADMOB_BANNER_ID_ANDROID');
  static const String _releaseInterstitialId =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ID_ANDROID');

  /// ビルド種別と注入値からユニットIDを決める（テストしやすいよう分離）
  @visibleForTesting
  static String? resolveUnitId({
    required bool isRelease,
    required String testId,
    required String releaseId,
  }) {
    if (!isRelease) return testId;
    return releaseId.isEmpty ? null : releaseId;
  }

  static String? get bannerId => resolveUnitId(
        isRelease: kReleaseMode,
        testId: testBannerId,
        releaseId: _releaseBannerId,
      );
  static String? get interstitialId => resolveUnitId(
        isRelease: kReleaseMode,
        testId: testInterstitialId,
        releaseId: _releaseInterstitialId,
      );

  // ── Banner ──
  static BannerAd? createBanner() {
    final unitId = bannerId;
    if (!_androidMobile || unitId == null) return null;
    final ad = BannerAd(
      size: AdSize.banner,
      adUnitId: unitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, err) { ad.dispose(); },
      ),
    )..load();
    return ad;
  }

  // ── Interstitial（先読み→1回表示） ──
  static InterstitialAd? _cached;

  static Future<void> prefetchInterstitial() async {
    final unitId = interstitialId;
    if (!_androidMobile || _cached != null || unitId == null) return;
    await InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _cached = ad,
        onAdFailedToLoad: (_) {},
      ),
    );
  }

  static Future<void> showInterstitialOnce() async {
    final ad = _cached;
    _cached = null;
    if (ad == null) return;
    await ad.show();
    ad.dispose();
    // 次回のために再度先読み（fire-and-forget）
    // unawaited(prefetchInterstitial()); を使わずに呼び出すだけでOK
    prefetchInterstitial();
  }
}
