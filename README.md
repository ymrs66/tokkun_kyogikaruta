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

## 署名

`android/key.properties` と `android/app/upload-keystore.jks`（いずれも Git 管理外）を使う。署名鍵は再生成しないこと。
