#!/bin/sh
# ios/scripts/admob_config.sh
#
# AdMob（iOS）の App ID をビルド済みの Info.plist に設定する。
# Xcode の Runner ターゲットのビルドフェーズ「AdMob Config」から呼ばれる。
#
# - Debug / Profile：Google 公式のテスト用 App ID（Debug.xcconfig・Release.xcconfig の
#   GAD_APPLICATION_IDENTIFIER、または下の既定値）
# - Release：Git 管理外の admob_release.json を
#     fvm flutter build ipa --release --dart-define-from-file=admob_release.json
#   で渡したときの dart-define（Flutter が Generated.xcconfig の DART_DEFINES に入れる）から
#   ADMOB_APP_ID_IOS を読み、検証してから設定する。
#   値が不足・形式不正・テスト ID の混入・パブリッシャー ID の不一致・未確認
#   （ADMOB_CONFIG_CONFIRMED_IOS が true でない）のときは **ビルドを止める**。
#
# 手順は README.md「AdMob 本番設定」を参照。Android 側は android/app/build.gradle.kts。

set -eu

TEST_APP_ID="ca-app-pub-3940256099942544~1458002511" # Google 公式のテスト用 iOS App ID
TEST_PUBLISHER="3940256099942544"
PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
BUDDY=/usr/libexec/PlistBuddy

if [ ! -f "$PLIST" ]; then
  echo "error: AdMob Config: Info.plist が見つかりません: $PLIST"
  exit 1
fi

# DART_DEFINES（base64 をカンマで連結したもの）から KEY の値を取り出す
define_value() {
  key="$1"
  old_ifs="$IFS"
  IFS=","
  for encoded in ${DART_DEFINES:-}; do
    decoded=$(printf '%s' "$encoded" | /usr/bin/base64 -D 2>/dev/null || true)
    case "$decoded" in
      "$key="*)
        IFS="$old_ifs"
        printf '%s' "${decoded#"$key="}"
        return 0
        ;;
    esac
  done
  IFS="$old_ifs"
  printf ''
}

publisher_of() {
  # ca-app-pub-<16桁><~ または /><10桁> の 16 桁部分。形式が違えば空
  printf '%s' "$1" | /usr/bin/sed -nE "s#^ca-app-pub-([0-9]{16})$2[0-9]{10}\$#\\1#p"
}

is_placeholder() {
  # ca-app-pub-<16桁>[~/]<10桁> のどちらかの数字部分が、同じ数字だけでできていれば真
  printf '%s' "$1" | /usr/bin/grep -Eq '^ca-app-pub-(0{16}|1{16}|2{16}|3{16}|4{16}|5{16}|6{16}|7{16}|8{16}|9{16})[~/]' && return 0
  printf '%s' "$1" | /usr/bin/grep -Eq '[~/](0{10}|1{10}|2{10}|3{10}|4{10}|5{10}|6{10}|7{10}|8{10}|9{10})$' && return 0
  return 1
}

set_app_id() {
  "$BUDDY" -c "Set :GADApplicationIdentifier $1" "$PLIST" 2>/dev/null \
    || "$BUDDY" -c "Add :GADApplicationIdentifier string $1" "$PLIST"
}

case "${CONFIGURATION:-}" in
  Release*)
    APP_ID=$(define_value ADMOB_APP_ID_IOS)
    BANNER=$(define_value ADMOB_BANNER_ID_IOS)
    INTERSTITIAL=$(define_value ADMOB_INTERSTITIAL_ID_IOS)
    CONFIRMED=$(define_value ADMOB_CONFIG_CONFIRMED_IOS)

    APP_PUB=$(publisher_of "$APP_ID" "~")
    BANNER_PUB=$(publisher_of "$BANNER" "/")
    INTER_PUB=$(publisher_of "$INTERSTITIAL" "/")

    ERRORS=""
    [ -n "$APP_PUB" ]    || ERRORS="$ERRORS\n - ADMOB_APP_ID_IOS が未設定または形式不正"
    [ -n "$BANNER_PUB" ] || ERRORS="$ERRORS\n - ADMOB_BANNER_ID_IOS が未設定または形式不正"
    [ -n "$INTER_PUB" ]  || ERRORS="$ERRORS\n - ADMOB_INTERSTITIAL_ID_IOS が未設定または形式不正"
    for pub in "$APP_PUB" "$BANNER_PUB" "$INTER_PUB"; do
      if [ "$pub" = "$TEST_PUBLISHER" ]; then
        ERRORS="$ERRORS\n - Release ビルドに Google のテスト ID が指定されています"
        break
      fi
    done
    # ひな形（admob_release.example.json の全桁 0）や 1111… などのダミー値を拒否する
    # （パブリッシャー ID・末尾の ID が同じ数字の繰り返しなら、実在の ID ではない）
    for id in "$APP_ID" "$BANNER" "$INTERSTITIAL"; do
      if is_placeholder "$id"; then
        ERRORS="$ERRORS\n - ひな形・ダミーの ID（同じ数字の繰り返し）が指定されています: $id"
      fi
    done
    if [ -n "$APP_PUB" ] && [ -n "$BANNER_PUB" ] && [ -n "$INTER_PUB" ]; then
      if [ "$APP_PUB" != "$BANNER_PUB" ] || [ "$APP_PUB" != "$INTER_PUB" ]; then
        ERRORS="$ERRORS\n - App ID と広告ユニット ID のパブリッシャー ID が一致しません"
      fi
    fi
    [ "$CONFIRMED" = "true" ] \
      || ERRORS="$ERRORS\n - ADMOB_CONFIG_CONFIRMED_IOS が true ではありません（AdMob 管理画面で確認後に true にする）"

    if [ -n "$ERRORS" ]; then
      printf "error: AdMob（iOS）の本番設定が不足しているため Release ビルドを中止しました:%b\n" "$ERRORS"
      echo "error: 手順: README.md「AdMob 本番設定」を参照し、--dart-define-from-file=admob_release.json を付けてビルドしてください。"
      exit 1
    fi

    set_app_id "$APP_ID"
    echo "AdMob Config: Release の App ID を設定しました（パブリッシャー ${APP_PUB}）"
    ;;
  Debug*)
    # UMP の本番メッセージの確認用（開発専用）：
    #   fvm flutter run --debug --dart-define=UMP_PREVIEW_APP_ID_IOS=<本番の iOS App ID>
    # App ID だけを本番にして、AdMob 管理画面で公開した同意メッセージを表示させる。
    # 広告ユニット ID は Debug なので Google のテスト ID のまま（アプリ側で固定）。Release・Profile では使わない。
    PREVIEW=$(define_value UMP_PREVIEW_APP_ID_IOS)
    if [ -n "$PREVIEW" ]; then
      PREVIEW_PUB=$(publisher_of "$PREVIEW" "~")
      if [ -z "$PREVIEW_PUB" ] || [ "$PREVIEW_PUB" = "$TEST_PUBLISHER" ] || is_placeholder "$PREVIEW"; then
        echo "error: AdMob Config: UMP_PREVIEW_APP_ID_IOS が iOS の App ID（ca-app-pub-<16桁>~<10桁>）ではありません: $PREVIEW"
        exit 1
      fi
      set_app_id "$PREVIEW"
      echo "warning: AdMob Config: UMP 確認用に本番の App ID を使用します（広告はテスト ID。Debug のみ）"
      exit 0
    fi
    CURRENT=$("$BUDDY" -c "Print :GADApplicationIdentifier" "$PLIST" 2>/dev/null || true)
    case "$CURRENT" in
      "ca-app-pub-${TEST_PUBLISHER}~"*) ;;
      *) set_app_id "$TEST_APP_ID" ;;
    esac
    echo "AdMob Config: ${CONFIGURATION:-?} はテスト用 App ID を使用します"
    ;;
  *)
    CURRENT=$("$BUDDY" -c "Print :GADApplicationIdentifier" "$PLIST" 2>/dev/null || true)
    case "$CURRENT" in
      "ca-app-pub-${TEST_PUBLISHER}~"*) ;;
      *) set_app_id "$TEST_APP_ID" ;;
    esac
    echo "AdMob Config: ${CONFIGURATION:-?} はテスト用 App ID を使用します"
    ;;
esac
