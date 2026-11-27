# 競技かるた特訓（tokkun_kyogikaruta）

百人一首の競技かるたを練習する Flutter アプリ（Android / iOS）。

- applicationId：`jp.ymrsystem.karutatokkun`
- バージョンは `pubspec.yaml` の `version` で管理する（`versionCode` / `versionName` は Gradle で直書きしない）

## 開発時（debug / profile）

```powershell
flutter pub get
flutter run
```

debug / profile ビルドでは、AdMob は常に **Google 配布のテスト ID** を使う。本番の広告 ID は使わない。

## AdMob 本番設定（release ビルド）

本番の App ID と広告ユニット ID は、**Git 管理外**の `admob_release.json` に置く（Android・iOS 共通の 1 ファイル）。このリポジトリは公開されているため、本番 ID をコミットしない。debug / profile ビルドは常に Google 公式のテスト ID を使う。

1. ひな形をコピーする

   ```powershell
   Copy-Item admob_release.example.json admob_release.json   # Windows
   ```

   ```bash
   cp admob_release.example.json admob_release.json          # Mac
   ```

2. `admob_release.json` に AdMob 管理画面の値を設定する（ビルドする OS の分だけでよい）

   | キー | 内容 |
   |---|---|
   | `ADMOB_APP_ID_ANDROID` | Android アプリの App ID（`ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX`） |
   | `ADMOB_BANNER_ID_ANDROID` | Android のバナーのユニット ID（`ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX`） |
   | `ADMOB_INTERSTITIAL_ID_ANDROID` | Android のインタースティシャルのユニット ID |
   | `ADMOB_CONFIG_CONFIRMED` | AdMob 管理画面で Android の上の3つを確認したら `"true"` にする |
   | `ADMOB_APP_ID_IOS` | iOS アプリの App ID |
   | `ADMOB_BANNER_ID_IOS` | iOS のバナーのユニット ID |
   | `ADMOB_INTERSTITIAL_ID_IOS` | iOS のインタースティシャルのユニット ID |
   | `ADMOB_CONFIG_CONFIRMED_IOS` | AdMob 管理画面で iOS の上の3つを確認したら `"true"` にする |

3. ファイルを指定して release ビルドする

   ```powershell
   flutter build appbundle --release --dart-define-from-file=admob_release.json   # Android（Windows）
   ```

   ```bash
   fvm flutter build ipa --release --dart-define-from-file=admob_release.json      # iOS（Mac）
   ```

   Xcode の Product → Archive を使う場合は、先に
   `fvm flutter build ios --config-only --release --dart-define-from-file=admob_release.json`
   を実行して、dart-define を Xcode の設定（`ios/Flutter/Generated.xcconfig`）に反映させる。

`admob_release.json` を指定しない場合や、値が不足・形式不正の場合、テスト ID が混ざっている場合、App ID と広告ユニット ID のパブリッシャー ID が一致しない場合、確認フラグが `"true"` でない場合は、**release ビルドを中止**する。

- Android：Gradle（`android/app/build.gradle.kts` の `validateAdmobReleaseConfig`）
- iOS：Xcode の Runner ターゲットのビルドフェーズ「AdMob Config」（`ios/scripts/admob_config.sh`）。検証に通ったときだけ、ビルド済みの Info.plist の `GADApplicationIdentifier` に本番の App ID を書き込む（debug はテスト用 App ID）
  - ひな形（全桁 0）や `1111…` のような同じ数字の繰り返しの ID もダミーとして拒否する
  - このフェーズは毎回実行される（増分ビルド・Xcode の Product → Archive でも省略されない）
  - スクリプトのテスト：`sh ios/scripts/test_admob_config.sh`

`ADMOB_CONFIG_CONFIRMED*` の `"true"` は「広告 ID を管理画面と照合済み」という意味で、プライバシー対応や配布の承認を意味しない。

## 広告の同意（UMP）

`lib/services/ad_consent.dart`。起動ごとに同意情報を更新し、必要なときだけ同意フォームを表示する。`canRequestAds()` が true のときだけ Mobile Ads SDK を初期化して広告を読み込む（Android・iOS 共通）。広告が出なくても練習・結果・ギャラリーの報酬は動く。

- 同意フォームは、AdMob 管理画面の「プライバシーとメッセージ」で該当地域（欧州・米国の州など）のメッセージを公開したときだけ表示される
- プライバシー オプションが必要な利用者には、設定画面に「広告のプライバシー設定」を表示する
- 広告の内容は一般向け（`maxAdContentRating: G`）までに制限する

### 同意フォームの確認（debug / profile のみ）

```bash
fvm flutter run --dart-define=UMP_DEBUG_GEOGRAPHY=eea                       # 欧州として扱う（シミュレーター）
fvm flutter run --dart-define=UMP_DEBUG_GEOGRAPHY=eea --dart-define=UMP_TEST_DEVICE_IDS=<ハッシュID>   # 実機
```

`UMP_DEBUG_GEOGRAPHY` は `eea` / `us_state` / `other`。実機のハッシュ ID は起動時のログに表示される。**release ビルドでは指定しても無効**（正式版に混入しない）。debug ではテスト用 App ID のため、Google のテスト用のフォームが表示される。

### TestFlight でのテスト広告

TestFlight のビルドは release のため本番の広告 ID を使う。確認する端末ではテスト広告を表示させ、広告はタップしない。方法は次のどちらか。

- AdMob 管理画面の「設定 → テストデバイス」に登録する（iOS は広告 ID（IDFA）で登録するため、トラッキングを許可していない端末では使えない場合がある）
- 端末のハッシュ ID（SDK のログ「To get test ads on this device…」）を指定してビルドする：
  `--dart-define=ADMOB_TEST_DEVICE_IDS=<ハッシュID>`（カンマ区切り、`admob_release.json` とは別に指定）。指定した端末だけがテスト広告になる

## 署名

`android/key.properties` と `android/app/upload-keystore.jks`（いずれも Git 管理外）を使う。署名鍵は再生成しないこと。
