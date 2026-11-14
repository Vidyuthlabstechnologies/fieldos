import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
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

// One codebase, one app per country (lib/core/market.dart). The market
// comes from the same --dart-define=FIELDOS_MARKET=us the Dart code reads
// (Flutter hands Gradle its dart-defines base64-encoded), so a build can't
// carry US code under the Indian app id or the other way round. No define:
// India, the original id, so the app already on Play keeps updating.
val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.mapNotNull { runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull() }
    ?.mapNotNull { kv -> kv.indexOf('=').takeIf { it > 0 }?.let { kv.substring(0, it) to kv.substring(it + 1) } }
    ?.toMap()
    ?: emptyMap()
val fieldosMarket = dartDefines["FIELDOS_MARKET"] ?: "in"
val appIdSuffix = mapOf("in" to "", "us" to ".us", "my" to ".my", "ae" to ".ae", "uk" to ".uk")[fieldosMarket]
    ?: throw GradleException("Unknown FIELDOS_MARKET '$fieldosMarket'; use in, us, my, ae or uk")

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
        applicationId = "com.mldynamic.fieldos$appIdSuffix"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 7.0+. (Was set for Chaquopy, removed in 1.7.4; kept so no
        // phone that installs today stops getting updates.)
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
