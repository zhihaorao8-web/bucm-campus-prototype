plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val versionManifest = javax.xml.parsers.DocumentBuilderFactory.newInstance()
    .newDocumentBuilder().parse(file("../../../AndroidManifest.xml")).documentElement
val isolatedParserTest = providers.gradleProperty("campusReleaseParserTest").orNull == "true"

android {
    namespace = "cn.bucm.campus_schedule"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    testBuildType = "release"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (isolatedParserTest) "cn.bucm.campus_schedule.releasetest" else "cn.bucm.campus_schedule"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // User-facing version and monotonic code always come from the root manifest.
        versionCode = versionManifest.getAttribute("android:versionCode").toInt()
        versionName = versionManifest.getAttribute("android:versionName")
    }

    buildTypes {
        release {
            // v0.1 is a pre-release, built in release mode using the existing local
            // development signer so installed previews can update without data loss.
            // This is not a production signing configuration; never commit this key.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (isolatedParserTest) proguardFiles("release-test-target-rules.pro")
            testProguardFiles("test-proguard-rules.pro")
        }
    }
}

// scripts/prepare_flutter.py copies only the tested UI-independent parsers.
dependencies {
    // AndroidX Media3, Apache-2.0; see docs/THIRD_PARTY.md.
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation(fileTree("libs") { include("*.jar") })
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

tasks.matching { it.name == "connectedReleaseAndroidTest" }.configureEach {
    doFirst {
        check(isolatedParserTest) { "Use -PcampusReleaseParserTest=true; never run parser instrumentation over a user's installed app." }
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
