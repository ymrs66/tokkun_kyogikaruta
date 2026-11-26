// 最上部に追加
import java.util.Properties
import java.util.Base64
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// key.properties を読む
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

// ── AdMob の App ID（debug=テスト / release=本番） ──────────────────
// 本番の ID は Git 管理外の admob_release.json に置き、
//   flutter build appbundle --release --dart-define-from-file=admob_release.json
// で渡す。Flutter は dart-define を "-Pdart-defines=<base64,...>" として Gradle に渡すので、
// ここで読み取って AndroidManifest の ${admobAppId} に設定する。
val admobTestAppId = "ca-app-pub-3940256099942544~3347511713" // Google 配布のテスト App ID
val admobTestPublisher = "3940256099942544"
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull { encoded ->
            runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }.getOrNull()
        }
        ?.mapNotNull { kv -> kv.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
        ?.toMap()
        ?: emptyMap()
val admobReleaseAppId: String = dartDefines["ADMOB_APP_ID_ANDROID"].orEmpty()

// release ビルドのときだけ、本番設定がそろっているかを確認する（不足していればビルドを止める）
fun validateAdmobReleaseConfig() {
    val appId = admobReleaseAppId
    val banner = dartDefines["ADMOB_BANNER_ID_ANDROID"].orEmpty()
    val interstitial = dartDefines["ADMOB_INTERSTITIAL_ID_ANDROID"].orEmpty()
    val confirmed = dartDefines["ADMOB_CONFIG_CONFIRMED"].orEmpty()
    val errors = mutableListOf<String>()
    val appIdRe = Regex("""^ca-app-pub-(\d{16})~\d{10}$""")
    val unitIdRe = Regex("""^ca-app-pub-(\d{16})/\d{10}$""")
    val appPub = appIdRe.find(appId)?.groupValues?.get(1)
    val bannerPub = unitIdRe.find(banner)?.groupValues?.get(1)
    val interPub = unitIdRe.find(interstitial)?.groupValues?.get(1)
    if (appPub == null) errors += "ADMOB_APP_ID_ANDROID が未設定または形式不正"
    if (bannerPub == null) errors += "ADMOB_BANNER_ID_ANDROID が未設定または形式不正"
    if (interPub == null) errors += "ADMOB_INTERSTITIAL_ID_ANDROID が未設定または形式不正"
    if (listOf(appPub, bannerPub, interPub).any { it == admobTestPublisher }) {
        errors += "release ビルドに Google のテスト ID が指定されています"
    }
    if (appPub != null && bannerPub != null && interPub != null &&
        setOf(appPub, bannerPub, interPub).size != 1) {
        errors += "App ID と広告ユニット ID のパブリッシャー ID が一致しません"
    }
    if (confirmed != "true") {
        errors += "ADMOB_CONFIG_CONFIRMED が true ではありません（AdMob 管理画面で確認後に true にする）"
    }
    if (errors.isNotEmpty()) {
        throw GradleException(
            "AdMob の本番設定が不足しているため release ビルドを中止しました:\n - " +
                errors.joinToString("\n - ") +
                "\n手順: README.md「AdMob 本番設定」を参照し、" +
                "--dart-define-from-file=admob_release.json を付けてビルドしてください。"
        )
    }
}
gradle.taskGraph.whenReady {
    val releasePackaging = Regex("""^(assemble|bundle|package)Release$""")
    if (allTasks.any { it.project == project && releasePackaging.matches(it.name) }) {
        validateAdmobReleaseConfig()
    }
}

android {
    namespace = "jp.ymrsystem.karutatokkun" // ←最終的なパッケージ名に変更推奨
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }

    defaultConfig {
        applicationId = "jp.ymrsystem.karutatokkun" // ←本番用に固有IDへ
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 既定（debug / profile）は AdMob のテスト App ID
        manifestPlaceholders["admobAppId"] = admobTestAppId
    }

    // ★ 署名設定を追加
    signingConfigs {
        create("release") {
            // key.properties が無い場合に備えて null 安全に
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword", storePassword)
            }
        }
    }

    buildTypes {
        release {
            // ★ debug 署名をやめて release 署名を使う
            signingConfig = signingConfigs.getByName("release")
            // release のみ本番 App ID（未設定ならビルド開始時に validateAdmobReleaseConfig で停止）
            manifestPlaceholders["admobAppId"] = admobReleaseAppId.ifEmpty { "ADMOB_APP_ID_NOT_SET" }
            isMinifyEnabled = false
            isShrinkResources = false
            // 必要なら難読化をONにして proguard-rules.pro を用意
            // proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
            ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
        }
        debug {
                // エミュレータ用に x86_64 を必ず入れる（明示でもOK・未指定でもOK）
                ndk { abiFilters += listOf("x86_64", "arm64-v8a", "armeabi-v7a") }
            }
        }
    }

flutter { source = "../.." }
