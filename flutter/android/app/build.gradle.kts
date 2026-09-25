plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun resolveTiRtcFlutterInternalReleaseKeystore(): File {
    val override = providers.gradleProperty("TIRTC_FLUTTER_ANDROID_INTERNAL_RELEASE_KEYSTORE").orNull
        ?: System.getenv("TIRTC_FLUTTER_ANDROID_INTERNAL_RELEASE_KEYSTORE")
    return if (override.isNullOrBlank()) {
        rootProject.file("tirtc-flutter-example-internal-release.keystore")
    } else {
        file(override.trim())
    }
}

android {
    namespace = "com.tange.ai.tirtc_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tange.ai.tirtc_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("internalRelease") {
            storeFile = resolveTiRtcFlutterInternalReleaseKeystore()
            storePassword = "tirtc-internal"
            keyAlias = "tirtc-flutter-example-internal-release"
            keyPassword = "tirtc-internal"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("internalRelease")
            ndk.abiFilters.clear()
            ndk.abiFilters.addAll(listOf("arm64-v8a"))
        }
        debug {
            ndk.abiFilters.clear()
            ndk.abiFilters.addAll(listOf("arm64-v8a"))
        }
    }

    packaging {
        jniLibs {
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86/**")
        }
    }
}

flutter {
    source = "../.."
}
