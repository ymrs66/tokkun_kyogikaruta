import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_consent.dart';
import '../services/ad_service.dart';

/// 画面下部のバナー広告。
///
/// UMP の同意確認で広告のリクエストが許可されたときだけ読み込む。許可が取り消されたら
/// 破棄し、利用者がプライバシー設定を変更したら（generation が変わったら）読み込み直す。
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  int? _loadedGeneration;

  @override
  void initState() {
    super.initState();
    if (!AdService.isSupportedPlatform) return;
    AdService.consent.state.addListener(_onConsentChanged);
    _sync(AdService.consent.state.value);
  }

  void _onConsentChanged() {
    if (!mounted) return;
    setState(() => _sync(AdService.consent.state.value));
  }

  void _sync(AdConsentState s) {
    if (!s.canRequestAds) {
      _disposeAd();
      return;
    }
    if (_ad != null && _loadedGeneration == s.generation) return;
    _disposeAd();
    _ad = AdService.createBanner();
    _loadedGeneration = _ad == null ? null : s.generation;
  }

  void _disposeAd() {
    _ad?.dispose();
    _ad = null;
    _loadedGeneration = null;
  }

  @override
  void dispose() {
    if (AdService.isSupportedPlatform) {
      AdService.consent.state.removeListener(_onConsentChanged);
    }
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
