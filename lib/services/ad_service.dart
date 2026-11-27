// lib/services/ad_service.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_consent.dart';
import 'interstitial_lifecycle.dart';

/// 広告ユニットIDの切り替え（Android・iOS 共通の仕組み、ID は OS 別）
///
/// - debug / profile ビルド：常に Google 配布のテストID（本番IDは使わない）
/// - release ビルド：`--dart-define-from-file=admob_release.json` で渡した本番ID
///   （admob_release.json は Git 管理外。手順は README.md「AdMob 本番設定」）
///
/// release で本番IDが渡されていない場合、Android は Gradle
/// （android/app/build.gradle.kts）、iOS は Xcode のビルドスクリプト
/// （ios/scripts/admob_config.sh）でビルドを止める。万一すり抜けた場合も広告を読み込まない。
///
/// 広告の読み込みは、UMP の同意確認で広告のリクエストが許可され、SDK を初期化した後だけ
/// （[consent]・lib/services/ad_consent.dart）。許可されていなければ広告は出さず、
/// 練習・結果・ギャラリーの報酬はそのまま動く。
class AdService {
  static bool get _android => !kIsWeb && Platform.isAndroid;
  static bool get _ios => !kIsWeb && Platform.isIOS;

  /// 広告を表示する OS（Android・iOS）。テスト実行中は読み込まない。
  static bool get isSupportedPlatform =>
      (_android || _ios) && !const bool.fromEnvironment('FLUTTER_TEST');

  /// 広告の同意と SDK の初期化の状態（テストではフェイクの platform に差し替える）
  static AdConsentController consent = AdConsentController(
    platform: UmpConsentPlatform(debugSettings: umpDebugSettingsFromEnvironment()),
    initializeAds: _initializeSdk,
  );

  /// 広告のリクエスト設定。広告の内容は一般向け（G）までに制限する。
  /// 年齢に応じた扱い（ageRestrictedTreatment）は未確定のため指定しない（報告書 105）。
  static RequestConfiguration get requestConfiguration => requestConfigurationFor(
        testDeviceIds: const String.fromEnvironment('ADMOB_TEST_DEVICE_IDS'),
      );

  /// [testDeviceIds]：テスト広告を表示する端末（SDK のログに出るハッシュ ID、カンマ区切り）。
  /// TestFlight で本番の広告 ID のビルドを確認するときに、自分の端末だけテスト広告にする
  /// （`--dart-define=ADMOB_TEST_DEVICE_IDS=...`）。指定しなければ null。
  @visibleForTesting
  static RequestConfiguration requestConfigurationFor({required String testDeviceIds}) {
    final ids = testDeviceIds
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return RequestConfiguration(
      maxAdContentRating: MaxAdContentRating.g,
      testDeviceIds: ids.isEmpty ? null : ids,
    );
  }

  static Future<void> _initializeSdk() async {
    // リクエスト設定は初期化の前に反映する（公式の targeting の手順）
    await MobileAds.instance.updateRequestConfiguration(requestConfiguration);
    await MobileAds.instance.initialize();
  }

  static bool _consentListening = false;

  /// 起動時に1回呼ぶ（main.dart）。同意を確認し、許可されたら SDK を初期化して先読みする。
  /// [waitForSafeMoment]：同意フォーム・ATT のダイアログを出してよい時（ホーム画面）まで待つ。
  static Future<void> start({Future<void> Function()? waitForSafeMoment}) async {
    if (!isSupportedPlatform) return;
    consent.waitForSafeMoment = waitForSafeMoment;
    if (!_consentListening) {
      _consentListening = true;
      var last = consent.state.value;
      consent.state.addListener(() {
        final now = consent.state.value;
        onConsentChanged(last, now);
        last = now;
      });
    }
    await consent.gather();
  }

  /// 同意状態の変化に合わせて、インタースティシャルを破棄・先読みし直す。
  @visibleForTesting
  static void onConsentChanged(AdConsentState before, AdConsentState after) {
    if (!after.canRequestAds) {
      _interstitial.clear();
      return;
    }
    if (after.generation != before.generation) {
      _interstitial.clear(); // 古い同意状態で読み込んだ広告は使わない
    }
    _interstitial.prefetch();
  }

  // Google配布のテストユニットID
  // Android: https://developers.google.com/admob/android/test-ads
  // iOS:     https://developers.google.com/admob/ios/test-ads
  static const String testBannerIdAndroid       = 'ca-app-pub-3940256099942544/6300978111';
  static const String testInterstitialIdAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const String testBannerIdIos           = 'ca-app-pub-3940256099942544/2934735716';
  static const String testInterstitialIdIos     = 'ca-app-pub-3940256099942544/4411468910';

  // 本番ユニットID：release ビルド時に dart-define で注入
  static const String _releaseBannerIdAndroid =
      String.fromEnvironment('ADMOB_BANNER_ID_ANDROID');
  static const String _releaseInterstitialIdAndroid =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ID_ANDROID');
  static const String _releaseBannerIdIos =
      String.fromEnvironment('ADMOB_BANNER_ID_IOS');
  static const String _releaseInterstitialIdIos =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ID_IOS');

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

  /// OS に応じたユニットID（テスト用・本番用）を選ぶ（テストしやすいよう分離）
  @visibleForTesting
  static String? unitIdFor({
    required bool ios,
    required bool isRelease,
    required bool banner,
  }) {
    if (ios) {
      return resolveUnitId(
        isRelease: isRelease,
        testId: banner ? testBannerIdIos : testInterstitialIdIos,
        releaseId: banner ? _releaseBannerIdIos : _releaseInterstitialIdIos,
      );
    }
    return resolveUnitId(
      isRelease: isRelease,
      testId: banner ? testBannerIdAndroid : testInterstitialIdAndroid,
      releaseId: banner ? _releaseBannerIdAndroid : _releaseInterstitialIdAndroid,
    );
  }

  static String? get bannerId =>
      unitIdFor(ios: _ios, isRelease: kReleaseMode, banner: true);
  static String? get interstitialId =>
      unitIdFor(ios: _ios, isRelease: kReleaseMode, banner: false);

  // ── Banner ──
  static BannerAd? createBanner() {
    final unitId = bannerId;
    if (!isSupportedPlatform || unitId == null || !consent.canRequestAds) return null;
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
    if (!isSupportedPlatform || unitId == null || !consent.canRequestAds) {
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
      onAdFailedToShowFullScreenContent: (_, _) => _interstitial.finishShow(ad),
    );
    try {
      await ad.show();
    } catch (_) {
      _interstitial.finishShow(ad);
    }
  }
}
