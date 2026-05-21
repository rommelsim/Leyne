import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config — loaded from android/key.properties, which is
// gitignored (it holds the keystore path + passwords). When that file is
// absent (CI, a fresh clone) the release build falls back to debug signing
// so `flutter build` still produces a runnable app; only a real Play Store
// upload needs the upload keystore.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.leyne.leyne"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.leyne.leyne"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Detail-screen map on Android is OpenStreetMap via flutter_map
        // (no key needed). The MAPS_API_KEY manifestPlaceholder that used
        // to be wired here was removed when we switched off
        // google_maps_flutter.
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real upload key when key.properties is present (Play Store
            // builds); debug signing otherwise so CI and fresh clones still
            // build a runnable release.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 code shrinking is OFF for release. The Google Mobile Ads
            // SDK starts WorkManager (androidx.work) at app launch, and R8's
            // obfuscation renamed the Room-generated WorkDatabase_Impl —
            // crashing the app on startup with "Failed to create an instance
            // of androidx.work.impl.WorkDatabase". The Java/Kotlin layer R8
            // would shrink is small next to the Flutter engine + AOT Dart,
            // so disabling it is the reliable trade-off.
            isMinifyEnabled = false
            isShrinkResources = false
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
