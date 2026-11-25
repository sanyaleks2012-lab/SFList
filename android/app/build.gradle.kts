plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin применяется после Android и Kotlin плагинов
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.SFRaidTeam.sflist"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.SFRaidTeam.sflist"
        minSdk = 24 // было flutter.minSdkVersion; Shizuku требует 24+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Для теста подписываем debug-ключом. Для публикации создайте свой signingConfig.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}