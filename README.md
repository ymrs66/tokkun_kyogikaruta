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

本番の App ID と広告ユニット ID は、**Git 管理外**の `admob_release.json` に置く。このリポジトリは公開されているため、本番 ID をコミットしない。

1. ひな形をコピーする

   ```powershell
   Copy-Item admob_release.example.json admob_release.json
   ```

2. `admob_release.json` に AdMob 管理画面の値を設定する

   | キー | 内容 |
   |---|---|
   | `ADMOB_APP_ID_ANDROID` | Android アプリの App ID（`ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX`） |
   | `ADMOB_BANNER_ID_ANDROID` | バナーのユニット ID（`ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX`） |
   | `ADMOB_INTERSTITIAL_ID_ANDROID` | インタースティシャルのユニット ID |
   | `ADMOB_CONFIG_CONFIRMED` | AdMob 管理画面で上の3つを確認したら `"true"` にする |

3. ファイルを指定して release ビルドする

   ```powershell
   flutter build appbundle --release --dart-define-from-file=admob_release.json
   ```

`admob_release.json` を指定しない場合や、値が不足・形式不正の場合、またはテスト ID が混ざっている場合は、Gradle が **release ビルドを中止**する（`android/app/build.gradle.kts` の `validateAdmobReleaseConfig`）。App ID と広告ユニット ID のパブリッシャー ID が一致しない場合も中止する。

## 署名

`android/key.properties` と `android/app/upload-keystore.jks`（いずれも Git 管理外）を使う。署名鍵は再生成しないこと。
