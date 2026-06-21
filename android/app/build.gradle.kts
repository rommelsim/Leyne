import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Compose compiler for Jetpack Glance home-screen widgets (@Composable
    // widget content). Must be applied alongside the Kotlin plugin; Glance does
    // NOT require buildFeatures.compose (that's for Compose UI) — only the
    // compiler plugin to process the @Composable widget functions.
    id("org.jetbrains.kotlin.plugin.compose")
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

// Firebase (Google Services) — apply the plugin only when google-services.json
// is present, mirroring the keystore guard above. The plugin reads that file to
// generate the values Firebase.initializeApp() consumes at runtime. Without it
// (fresh clone / CI / before Firebase is configured) we skip the plugin so the
// build still succeeds; Firebase.initializeApp() is wrapped in main.dart so
// analytics degrade to a no-op instead of crashing. To activate Android
// analytics: export google-services.json from the Firebase console (package
// com.leyne.leyne) into android/app/, then rebuild.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.leyne.leyne"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Core library desugaring — required by flutter_local_notifications
        // so its java.time usage compiles down to Android's pre-API-26
        // Joda-backed equivalents. Without this the bundleRelease task
        // fails with "Dependency ':flutter_local_notifications' requires
        // core library desugaring to be enabled for :app."
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.leyne.leyne"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Maps use flutter_map with free CartoDB tiles — no API key, no
        // billing, no manifest placeholder needed.

        // LTA DataMall key for the Kotlin/Glance widget refresh worker. The
        // Glance widgets cannot call into the Dart runtime, so WidgetRefreshWorker
        // hits v3/BusArrival directly and needs the key at the native layer.
        // Sourced from the LTA_API_KEY env var (CI / local), falling back to the
        // same embedded key the Dart side uses (lib/data/lta_config.dart) so a
        // plain `flutter build` still produces working widgets.
        buildConfigField(
            "String",
            "LTA_API_KEY",
            "\"${System.getenv("LTA_API_KEY") ?: "+6zJ3XstTqOcDkvczHttWA=="}\"",
        )
    }

    // BuildConfig.LTA_API_KEY above requires the buildConfig feature; AGP 8+
    // defaults it off.
    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // rootProject.file() resolves a relative storeFile against the
                // android/ dir (so a repo-local, gitignored keystore is portable
                // across machines/CI); an absolute path is still honored as-is.
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { rootProject.file(it) }
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

// Core library desugaring dependency — pairs with
// `isCoreLibraryDesugaringEnabled = true` above. Version chosen to match
// what flutter_local_notifications' setup docs recommend; bumping this is
// safe within the major (2.x).
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Jetpack Glance — the home-screen widgets are written in a Compose-like
    // Kotlin DSL that compiles down to RemoteViews. Does not pull Compose into
    // the Flutter app process; only the widget RemoteViews use it.
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")
    // WorkManager backstop that refreshes widget arrivals when the app is closed.
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    // StopPicker / FavPicker widget-configuration activities use AppCompat.
    implementation("androidx.appcompat:appcompat:1.7.0")
    // Location services for Nearby. geolocator pulls play-services-location
    // transitively, but we declare it explicitly so the API version is pinned
    // and not left to dependency resolution.
    implementation("com.google.android.gms:play-services-location:21.3.0")
}
