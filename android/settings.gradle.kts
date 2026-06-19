pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Compose compiler — required by Jetpack Glance, whose home-screen widget
    // content is written as @Composable functions. Version tracks the Kotlin
    // version. Applied in app/build.gradle.kts.
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.20" apply false
    // Firebase config processor. Applied (conditionally, see app/build.gradle.kts)
    // only when google-services.json is present, so a clone without the Firebase
    // config still builds.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
