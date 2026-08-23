plugins {
    id("com.android.application")
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.predictera.fieldos_mobile"
    // flutter.compileSdkVersion currently resolves to 34, which is too low
    // for flutter_plugin_android_lifecycle (a transitive dep of file_picker,
    // requires >=36) -- override explicitly rather than relying on Flutter's
    // computed value.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.predictera.fieldos_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Chaquopy 17+ requires minSdk >= 24.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // Chaquopy's Python 3.13 distribution only supports these two
            // ABIs -- must REPLACE Flutter's own default filter set (which
            // includes armeabi-v7a), not add to it.
            abiFilters.clear()
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // Only the pure-stdlib estimation_calc.py is bundled here (see
    // src/main/python/) -- no pip dependencies needed, and none should be
    // added without re-checking Chaquopy's package repository first (see
    // docs/CHAQUOPY_FEASIBILITY.md for why pydantic/bcrypt/sqlalchemy etc.
    // are NOT safe to add here).
    chaquopy {
        defaultConfig {
            version = "3.13"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
