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
    // AGP 8.12+ required by newer plugins (e.g. share_plus). Stay on AGP 8.x while
    // Flutter 3.44 keeps android.builtInKotlin=false for unmigrated plugins.
    id("com.android.application") version "8.12.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.10" apply false
}

include(":app")
