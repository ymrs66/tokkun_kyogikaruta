// lib/services/ad_service.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'interstitial_lifecycle.dart';

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

  // ── Interstitial（先読み→1回表示→閉じたら解放→次を先読み） ──
  static final InterstitialLifecycle<InterstitialAd> _interstitial =
      InterstitialLifecycle<InterstitialAd>(
    loadAd: _loadInterstitial,
    disposeAd: (ad) => ad.dispose(),
  );

  static void _loadInterstitial(
    void Function(InterstitialAd ad) onLoaded,
    void Function() onFailed,
  ) {
    final unitId = interstitialId;
    if (!_androidMobile || unitId == null) {
      onFailed();
      return;
    }
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: (_) => onFailed(),
      ),
    ).catchError((Object _) => onFailed());
  }

  /// 次の表示のために先読みする（読み込み中・読み込み済みなら何もしない）。
  static Future<void> prefetchInterstitial() async {
    _interstitial.prefetch();
  }

  /// 読み込み済みの広告があれば1回表示する。広告がない・表示中なら何もしない。
  /// 広告を閉じた／表示に失敗したときに解放し、次を先読みする。
  /// 呼び出し側（結果画面）の進行は、広告の有無や結果を待たずに続けてよい。
  static Future<void> showInterstitialOnce() async {
    final ad = _interstitial.takeForShow();
    if (ad == null) return;
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (_) => _interstitial.finishShow(ad),
      onAdFailedToShowFullScreenContent: (_, __) => _interstitial.finishShow(ad),
    );
    try {
      await ad.show();
    } catch (_) {
      _interstitial.finishShow(ad);
    }
  }
}
