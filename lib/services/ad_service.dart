// lib/services/ad_service.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static bool get _androidMobile => Platform.isAndroid && !kIsWeb;

  // Google配布のテストユニットID（Android）
  static String get bannerId        => 'ca-app-pub-3940256099942544/6300978111';
  static String get interstitialId  => 'ca-app-pub-3940256099942544/1033173712';

  // ── Banner ──
  static BannerAd? createBanner() {
    if (!_androidMobile) return null;
    final ad = BannerAd(
      size: AdSize.banner,
      adUnitId: bannerId,
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
    if (!_androidMobile || _cached != null) return;
    await InterstitialAd.load(
      adUnitId: interstitialId,
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
