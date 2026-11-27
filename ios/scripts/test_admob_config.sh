#!/bin/sh
# ios/scripts/test_admob_config.sh
#
# ios/scripts/admob_config.sh（AdMob の App ID 設定・Release の検証）のテスト。
# Xcode は不要。一時フォルダの Info.plist に対してスクリプトを実行し、結果を確かめる。
#
#   sh ios/scripts/test_admob_config.sh
#
# ここで使う ID はすべてダミー（実在しないパブリッシャー ID）か Google 公式のテスト ID。

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET="$SCRIPT_DIR/admob_config.sh"
SRC_PLIST="$SCRIPT_DIR/../Runner/Info.plist"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/admob_config_test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

TEST_APP_ID="ca-app-pub-3940256099942544~1458002511"
P="1234567890123456" # ダミー（同じ数字の繰り返しではない）
FAILED=0

enc() { printf '%s' "$1" | /usr/bin/base64; }

defines() {
  # 引数: KEY=VALUE ... → DART_DEFINES の形式（base64 をカンマ区切り）
  out=""
  for kv in "$@"; do
    if [ -z "$out" ]; then out=$(enc "$kv"); else out="$out,$(enc "$kv")"; fi
  done
  printf '%s' "$out"
}

valid_ios() {
  defines "ADMOB_APP_ID_IOS=ca-app-pub-$P~2468013579" \
          "ADMOB_BANNER_ID_IOS=ca-app-pub-$P/3579024681" \
          "ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-$P/1357924680" \
          "ADMOB_CONFIG_CONFIRMED_IOS=true"
}

# run <name> <configuration> <dart_defines> <expect: ok|fail> [expected app id]
run() {
  name="$1"; config="$2"; dd="$3"; expect="$4"; want="${5:-}"
  cp "$SRC_PLIST" "$WORK/Info.plist"
  out=$(env TARGET_BUILD_DIR="$WORK" INFOPLIST_PATH=Info.plist CONFIGURATION="$config" \
        DART_DEFINES="$dd" sh "$TARGET" 2>&1)
  status=$?
  got=$(/usr/libexec/PlistBuddy -c 'Print :GADApplicationIdentifier' "$WORK/Info.plist" 2>/dev/null)
  result="ok"
  [ $status -eq 0 ] || result="fail"
  pass=1
  [ "$result" = "$expect" ] || pass=0
  if [ -n "$want" ] && [ "$got" != "$want" ]; then pass=0; fi
  # 失敗したときに Info.plist に本番扱いの値が書かれていないこと
  if [ "$result" = "fail" ] && [ "$got" != '$(GAD_APPLICATION_IDENTIFIER)' ]; then pass=0; fi
  if [ $pass -eq 1 ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (exit=$status, plist=$got)"
    echo "$out" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi
}

run "Debug はテスト用 App ID"                 Debug   ""            ok   "$TEST_APP_ID"
run "Profile はテスト用 App ID（本番の値があっても）" Profile "$(valid_ios)" ok   "$TEST_APP_ID"
run "Release：設定なしは中止"                  Release ""            fail
run "Release：Android のキーだけでは中止" Release \
  "$(defines "ADMOB_APP_ID_ANDROID=ca-app-pub-$P~2468013579" "ADMOB_CONFIG_CONFIRMED=true")" fail
run "Release：ひな形（全桁 0）は確認済みでも中止" Release \
  "$(defines "ADMOB_APP_ID_IOS=ca-app-pub-0000000000000000~0000000000" \
             "ADMOB_BANNER_ID_IOS=ca-app-pub-0000000000000000/0000000000" \
             "ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-0000000000000000/0000000000" \
             "ADMOB_CONFIG_CONFIRMED_IOS=true")" fail
run "Release：1111… のダミーは中止" Release \
  "$(defines "ADMOB_APP_ID_IOS=ca-app-pub-1111111111111111~2222222222" \
             "ADMOB_BANNER_ID_IOS=ca-app-pub-1111111111111111/3333333333" \
             "ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-1111111111111111/4444444444" \
             "ADMOB_CONFIG_CONFIRMED_IOS=true")" fail
run "Release：末尾の ID だけ全桁 0 でも中止" Release \
  "$(defines "ADMOB_APP_ID_IOS=ca-app-pub-$P~2468013579" \
             "ADMOB_BANNER_ID_IOS=ca-app-pub-$P/0000000000" \
             "ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-$P/1357924680" \
             "ADMOB_CONFIG_CONFIRMED_IOS=true")" fail
run "Release：Google のテスト ID は中止" Release \
  "$(defines "ADMOB_APP_ID_IOS=$TEST_APP_ID" \
             "ADMOB_BANNER_ID_IOS=ca-app-pub-3940256099942544/2934735716" \
             "ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-3940256099942544/4411468910" \
             "ADMOB_CONFIG_CONFIRMED_IOS=true")" fail
run "Release：パブリッシャー ID の不一致は中止" Release \
  "$(defines "ADMOB_APP_ID_IOS=ca-app-pub-$P~2468013579" \
             "ADMOB_BANNER_ID_IOS=ca-app-pub-6543210987654321/3579024681" \
             "ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-$P/1357924680" \
             "ADMOB_CONFIG_CONFIRMED_IOS=true")" fail
run "Release：未確認（CONFIRMED_IOS=false）は中止" Release \
  "$(defines "ADMOB_APP_ID_IOS=ca-app-pub-$P~2468013579" \
             "ADMOB_BANNER_ID_IOS=ca-app-pub-$P/3579024681" \
             "ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-$P/1357924680" \
             "ADMOB_CONFIG_CONFIRMED_IOS=false")" fail
run "Release：形式不正は中止" Release \
  "$(defines "ADMOB_APP_ID_IOS=ca-app-pub-$P/2222222222" \
             "ADMOB_BANNER_ID_IOS=ca-app-pub-$P/3579024681" \
             "ADMOB_INTERSTITIAL_ID_IOS=ca-app-pub-$P/1357924680" \
             "ADMOB_CONFIG_CONFIRMED_IOS=true")" fail
run "Release：正しい形式の値は App ID を設定" Release "$(valid_ios)" ok "ca-app-pub-$P~2468013579"

# UMP の本番メッセージの確認用（UMP_PREVIEW_APP_ID_IOS）：Debug だけで有効、Release の保護は変わらない
PREVIEW="ca-app-pub-$P~9081726354"
run "Debug：UMP 確認用の App ID を設定" Debug "$(defines "UMP_PREVIEW_APP_ID_IOS=$PREVIEW")" ok "$PREVIEW"
run "Debug：UMP 確認用にテスト ID は中止" Debug \
  "$(defines "UMP_PREVIEW_APP_ID_IOS=$TEST_APP_ID")" fail
run "Debug：UMP 確認用にひな形は中止" Debug \
  "$(defines "UMP_PREVIEW_APP_ID_IOS=ca-app-pub-0000000000000000~0000000000")" fail
run "Debug：UMP 確認用に広告ユニット ID（/）は中止" Debug \
  "$(defines "UMP_PREVIEW_APP_ID_IOS=ca-app-pub-$P/9081726354")" fail
run "Profile：UMP 確認用は無視してテスト用 App ID" Profile \
  "$(defines "UMP_PREVIEW_APP_ID_IOS=$PREVIEW")" ok "$TEST_APP_ID"
run "Release：UMP 確認用だけでは中止" Release \
  "$(defines "UMP_PREVIEW_APP_ID_IOS=$PREVIEW")" fail
run "Release：UMP 確認用があっても本番設定の App ID を使う" Release \
  "$(valid_ios),$(enc "UMP_PREVIEW_APP_ID_IOS=$PREVIEW")" ok "ca-app-pub-$P~2468013579"

if [ $FAILED -eq 0 ]; then
  echo "All admob_config.sh tests passed."
else
  echo "$FAILED test(s) failed."
  exit 1
fi
