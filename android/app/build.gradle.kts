import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "auravation.arbiter.mock_server"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "auravation.arbiter.mock_server"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Only configure signing if keystore properties exist
            if (keystorePropertiesFile.exists()) {
                signingConfigs.create("release") {
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                    storePassword = keystoreProperties["storePassword"] as String
                }
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Embedded HTTP server for the on-device Wi-Fi file server (native, Android-only)
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    // Storage Access Framework navigation for the user-picked shared folder
    implementation("androidx.documentfile:documentfile:1.0.1")
    // Background media scanning (off the main thread, cancellable)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    // On-the-fly transcoding (Tier 3). LGPL "video" package: adds libvpx (VP9 software
    // encode) over the "min" package's built-in decoders. Switched from "min" +
    // Android's hardware MediaCodec encoder after both FFmpeg's h264_mediacodec wrapper
    // AND direct MediaCodec calls hung on this device's Samsung Exynos AVC encoder
    // (OMXNodeInstance UnsupportedIndex errors, encoder never leaves CONFIGURED state) —
    // libvpx-vp9 is pure CPU software encoding, sidestepping the vendor hardware encoder
    // entirely. Accepted tradeoff: Safari's native HLS/video doesn't support VP9, so
    // Tier-3-converted files won't play there (Direct Play/Remux files are unaffected).
    // Community-maintained continuation of the retired arthenica/ffmpeg-kit project.
    implementation("com.antonkarpenko:ffmpeg-kit-video:2.2.0")
}
