import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.SFRaidTeam.sflist"
    compileSdk = 36 // 36 — минимум, который требуют зависимости плагинов (androidx / lifecycle)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "com.SFRaidTeam.sflist"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Для теста подписываем debug-ключом. Для публикации нужен свой signingConfig.
            signingConfig = signingConfigs.getByName("debug")

            // Keep-правила для Shizuku: ShizukuChannel вызывает приватный
            // Shizuku.newProcess через reflection, а R8 в release вырезает такие методы.
            // Без этой строки Shizuku работает в debug, но ломается в release-APK.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}
