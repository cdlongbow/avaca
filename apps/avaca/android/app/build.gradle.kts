import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val requireReleaseSigning = (System.getenv("AVACA_REQUIRE_RELEASE_SIGNING") ?: "")
    .equals("true", ignoreCase = true)
val arm64Only = (System.getenv("AVACA_ANDROID_ARM64_ONLY") ?: "")
    .equals("true", ignoreCase = true)
if (requireReleaseSigning && !keystorePropertiesFile.exists()) {
    error("AVACA_REQUIRE_RELEASE_SIGNING requires android/key.properties")
}

android {
    namespace = "com.avaca.avaca"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.avaca.avaca"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (arm64Only) {
            ndk {
                abiFilters.add("arm64-v8a")
            }
        }
    }

    packaging {
        jniLibs {
            if (arm64Only) {
                excludes += setOf(
                    "**/armeabi-v7a/**",
                    "**/x86/**",
                    "**/x86_64/**",
                )
            }
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Local builds fall back to the debug key; the release workflow
            // supplies key.properties and requires the dedicated config.
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
