import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material. The keystore and key.properties are both
// git-ignored, so they exist only on a machine that has been set up for
// release builds. Credentials come from `key.properties` or the `LOVE_*`
// environment variables, so a CI build can supply them without a file.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun secret(key: String, fallback: String): String =
    (keystoreProperties.getProperty(key) ?: System.getenv("LOVE_${key.uppercase()}") ?: fallback)

android {
    namespace = "lk.lovelaundry.love_mobi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "lk.lovelaundry.love_mobi"
        // mobile_scanner + image_picker both require API 21+; 23 is the floor
        // Flutter itself now supports for its own runtime features.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    androidResources {
        localeFilters += listOf("en")
    }

    // A debug-signed release is installable but can never be replaced by a
    // store build — the signatures differ, so every future update is rejected.
    // Producing one silently is worse than failing: the artefact looks exactly
    // like a real release. The opt-out exists for local smoke builds only.
    val releaseKeystore = rootProject.file("love-laundry-release.jks")
    val hasReleaseKey = releaseKeystore.exists()
    val allowDebugRelease =
        System.getenv("LOVE_ALLOW_DEBUG_RELEASE") == "true" ||
            keystoreProperties.getProperty("allowDebugRelease") == "true"
    if (!hasReleaseKey && !allowDebugRelease) {
        throw GradleException(
            "Release signing key not found at ${releaseKeystore.path}. " +
                "It is git-ignored, so every fresh clone starts without one. " +
                "Copy your upload key there and set storePassword, keyAlias and " +
                "keyPassword in android/key.properties (or the LOVE_* env vars). " +
                "Set LOVE_ALLOW_DEBUG_RELEASE=true only for a throwaway local build."
        )
    }
    if (!hasReleaseKey) {
        logger.warn(
            "LOVE_ALLOW_DEBUG_RELEASE is set: signing the release build with the " +
                "DEBUG key. This artefact cannot be updated by a store build."
        )
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = secret("storePassword", "lovelaundry2026")
                keyAlias = secret("keyAlias", "lovelaundry")
                keyPassword = secret("keyPassword", "lovelaundry2026")
            }
        }
    }

    buildTypes {
        release {
            // No silent fallback: the configuration phase above has already
            // rejected a missing key unless the opt-out was set explicitly.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
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
