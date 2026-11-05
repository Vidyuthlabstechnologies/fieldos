import java.util.Properties

plugins {
    id("com.android.application")
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads android/app/key.properties (gitignored -- it holds
// the upload-key passwords). When it's absent (fresh clone, CI), release
// falls back to debug signing so `flutter build apk --release` still works
// for local verification; only a key.properties build is shippable.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("app/key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
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
        // Required by flutter_local_notifications (java.time on minSdk 24).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mldynamic.fieldos"
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

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real upload-key signing when key.properties exists (see note
            // above); debug keys otherwise, for build-verification only.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
