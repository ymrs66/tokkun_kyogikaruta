// lib/services/ad_consent.dart
//
// 広告の同意（UMP：User Messaging Platform）の確認と、広告の初期化の順序をまとめる。
//
// 公式の手順（https://developers.google.com/admob/flutter/privacy）に沿って、
//  1. 起動ごとに requestConsentInfoUpdate() で同意情報を更新する
//  2. 必要なときだけ同意フォームを表示する（loadAndShowConsentFormIfRequired）。
//     iOS では AdMob の IDFA 説明メッセージを公開すると、UMP が説明 → ATT のダイアログを表示する
//     （EEA では欧州の規制のメッセージが先）。フォームはホーム画面にいるときだけ表示する
//     （練習を始めた後にフォームやダイアログが重ならないように。[waitForSafeMoment]）
//  3. canRequestAds() が true のときだけ Mobile Ads SDK を初期化し、広告を読み込む
//     （更新に失敗しても、前回の起動時の同意状態で canRequestAds() を判断できる）
//  4. プライバシー オプションが必要なら、設定画面に「広告のプライバシー設定」を出す
//
// 地域の判定は UMP SDK に任せる（GPS や外部の IP 検索は使わない）。同意フォームが
// 表示されるのは、AdMob の管理画面で該当地域のメッセージを公開している場合だけ。
//
// SDK を直接呼ぶ部分は [ConsentPlatform] に分け、単体テストではフェイクに差し替える。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 広告の同意に関する状態（画面・広告の読み込みが参照する）
@immutable
class AdConsentState {
  const AdConsentState({
    this.canRequestAds = false,
    this.privacyOptionsRequired = false,
    this.generation = 0,
  });

  /// 広告をリクエストしてよいか（UMP の canRequestAds() かつ SDK の初期化済み）
  final bool canRequestAds;

  /// 設定画面に「広告のプライバシー設定」を出す必要があるか
  final bool privacyOptionsRequired;

  /// 利用者がプライバシー設定を開き直すたびに増える。読み込み済みの広告を作り直す合図
  final int generation;

  AdConsentState copyWith({bool? canRequestAds, bool? privacyOptionsRequired, int? generation}) =>
      AdConsentState(
        canRequestAds: canRequestAds ?? this.canRequestAds,
        privacyOptionsRequired: privacyOptionsRequired ?? this.privacyOptionsRequired,
        generation: generation ?? this.generation,
      );

  @override
  bool operator ==(Object other) =>
      other is AdConsentState &&
      other.canRequestAds == canRequestAds &&
      other.privacyOptionsRequired == privacyOptionsRequired &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(canRequestAds, privacyOptionsRequired, generation);

  @override
  String toString() =>
      'AdConsentState(canRequestAds: $canRequestAds, privacyOptionsRequired: $privacyOptionsRequired, generation: $generation)';
}

/// UMP SDK の呼び出し（テストではフェイクに差し替える）
abstract class ConsentPlatform {
  /// 同意情報を更新する。成功なら true、失敗（オフラインなど）なら false。
  Future<bool> requestConsentInfoUpdate();

  /// 必要なときだけ同意フォームを読み込んで表示し、閉じるまで待つ。
  Future<void> loadAndShowConsentFormIfRequired();

  Future<bool> canRequestAds();

  Future<bool> isPrivacyOptionsRequired();

  /// プライバシー オプションのフォームを表示し、閉じるまで待つ。
  Future<void> showPrivacyOptionsForm();
}

/// 同意の確認 → SDK の初期化 → 広告の読み込み可否、を管理する。
class AdConsentController {
  AdConsentController({
    required this.platform,
    required this.initializeAds,
    this.waitForSafeMoment,
  });

  final ConsentPlatform platform;

  /// 同意フォーム（iOS では IDFA の説明 → ATT のダイアログを含む）を表示してよい時まで待つ。
  /// アプリではホーム画面に戻るまで待つ（練習中にフォームが重なって練習が進まないように）。
  /// null なら待たない。
  Future<void> Function()? waitForSafeMoment;

  /// Mobile Ads SDK の初期化（1回だけ呼ぶ）
  final Future<void> Function() initializeAds;

  final ValueNotifier<AdConsentState> state = ValueNotifier(const AdConsentState());

  /// 同意フォームの読み込み・表示中（ホーム画面はこの間、練習を始めない）
  final ValueNotifier<bool> formInProgress = ValueNotifier(false);

  Future<void>? _gathering;
  Future<void>? _initializing;
  bool _adsInitialized = false;

  bool get adsInitialized => _adsInitialized;
  bool get canRequestAds => state.value.canRequestAds;

  /// 起動時に1回呼ぶ。実行中に重ねて呼ばれたら、同じ処理の完了を待つ。
  Future<void> gather() => _gathering ??= _gather().whenComplete(() => _gathering = null);

  Future<void> _gather() async {
    bool updated;
    try {
      updated = await platform.requestConsentInfoUpdate();
    } catch (_) {
      updated = false;
    }
    if (updated) {
      try {
        final wait = waitForSafeMoment;
        if (wait != null) await wait();
        formInProgress.value = true;
        try {
          await platform.loadAndShowConsentFormIfRequired();
        } finally {
          formInProgress.value = false;
        }
      } catch (_) {
        // フォームの読み込み・表示に失敗しても、下で canRequestAds() を確認する
      }
    }
    // 更新に失敗した場合も、UMP は前回の起動時の同意状態で判断する（公式の手順どおり）
    await _refresh();
  }

  /// 設定画面の「広告のプライバシー設定」から呼ぶ。
  Future<void> showPrivacyOptions() async {
    try {
      await platform.showPrivacyOptionsForm();
    } catch (_) {
      // 表示に失敗しても状態だけは確認し直す
    }
    await _refresh(bumpGeneration: true);
  }

  Future<void> _refresh({bool bumpGeneration = false}) async {
    bool can;
    bool privacy;
    try {
      can = await platform.canRequestAds();
    } catch (_) {
      can = false;
    }
    try {
      privacy = await platform.isPrivacyOptionsRequired();
    } catch (_) {
      privacy = false;
    }
    if (can) {
      can = await _ensureInitialized();
    }
    final cur = state.value;
    state.value = cur.copyWith(
      canRequestAds: can,
      privacyOptionsRequired: privacy,
      generation: bumpGeneration ? cur.generation + 1 : cur.generation,
    );
  }

  /// SDK を1回だけ初期化する。失敗したら広告を読み込まない（false）。
  Future<bool> _ensureInitialized() async {
    if (_adsInitialized) return true;
    try {
      await (_initializing ??= initializeAds());
      _adsInitialized = true;
    } catch (_) {
      _initializing = null; // 次の確認で再試行できるようにする
    }
    return _adsInitialized;
  }
}

/// 実際の UMP SDK（google_mobile_ads に同梱）を使う実装
class UmpConsentPlatform implements ConsentPlatform {
  UmpConsentPlatform({this.debugSettings});

  /// デバッグ用の地域・テスト端末。**release ビルドでは常に null**（[umpDebugSettingsFromEnvironment]）
  final ConsentDebugSettings? debugSettings;

  @override
  Future<bool> requestConsentInfoUpdate() {
    final done = Completer<bool>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(consentDebugSettings: debugSettings),
      () => done.complete(true),
      (FormError _) => done.complete(false),
    );
    return done.future;
  }

  @override
  Future<void> loadAndShowConsentFormIfRequired() {
    final done = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((FormError? _) => done.complete());
    return done.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> isPrivacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptionsForm() {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? _) => done.complete());
    return done.future;
  }
}

/// UMP のデバッグ設定（地域の上書き・テスト端末）。
///
/// debug / profile ビルドで、次の dart-define を付けたときだけ有効：
///   --dart-define=UMP_DEBUG_GEOGRAPHY=eea（eea / us_state / other）
///   --dart-define=UMP_TEST_DEVICE_IDS=<端末のハッシュ ID>（カンマ区切り）
/// release ビルドでは、指定があっても **常に null**（正式版に混入しない）。
ConsentDebugSettings? umpDebugSettingsFor({
  required bool isRelease,
  required String geography,
  required String testDeviceIds,
}) {
  if (isRelease) return null;
  final geo = switch (geography.trim().toLowerCase()) {
    'eea' => DebugGeography.debugGeographyEea,
    'us_state' => DebugGeography.debugGeographyRegulatedUsState,
    'other' => DebugGeography.debugGeographyOther,
    _ => null,
  };
  final ids = testDeviceIds
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (geo == null && ids.isEmpty) return null;
  return ConsentDebugSettings(debugGeography: geo, testIdentifiers: ids.isEmpty ? null : ids);
}

ConsentDebugSettings? umpDebugSettingsFromEnvironment() => umpDebugSettingsFor(
      isRelease: kReleaseMode,
      geography: const String.fromEnvironment('UMP_DEBUG_GEOGRAPHY'),
      testDeviceIds: const String.fromEnvironment('UMP_TEST_DEVICE_IDS'),
    );
