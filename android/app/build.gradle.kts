// 最上部に追加
import java.util.Properties
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
