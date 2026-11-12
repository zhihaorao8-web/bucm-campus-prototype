plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val versionManifest = javax.xml.parsers.DocumentBuilderFactory.newInstance()
    .newDocumentBuilder().parse(file("../../../AndroidManifest.xml")).documentElement
val isolatedParserTest = providers.gradleProperty("campusReleaseParserTest").orNull == "true"
val isolatedMediaTest = providers.gradleProperty("campusMediaTest").orNull == "true"
check(!(isolatedParserTest && isolatedMediaTest)) { "Choose one isolated instrumentation target." }

android {
    namespace = "cn.bucm.campus_schedule"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    testBuildType = if (isolatedMediaTest) "debug" else "release"

    sourceSets.getByName("androidTest") {
        if (isolatedMediaTest) {
            java.setSrcDirs(listOf("src/mediaTest/java"))
            assets.setSrcDirs(listOf(project.layout.buildDirectory.dir("generated/synthetic-media")))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = when {
            isolatedParserTest -> "cn.bucm.campus_schedule.releasetest"
            isolatedMediaTest -> "cn.bucm.campus_schedule.mediatest"
            else -> "cn.bucm.campus_schedule"
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        if (isolatedMediaTest) {
            testInstrumentationRunnerArguments["class"] = "cn.bucm.campus_schedule.MediaPlaybackTest"
        }
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
    if (isolatedMediaTest) {
        // integration_test contributes an older runner to debug. AGP requires
        // consistent app/test resolution; align only this isolated target.
        debugImplementation("androidx.test:runner:1.6.2")
        debugImplementation("androidx.test.ext:junit:1.2.1")
    }
}

tasks.matching { it.name == "connectedReleaseAndroidTest" }.configureEach {
    doFirst {
        check(isolatedParserTest) { "Use -PcampusReleaseParserTest=true; never run parser instrumentation over a user's installed app." }
    }
}
tasks.matching { it.name == "connectedDebugAndroidTest" }.configureEach {
    doFirst {
        check(isolatedMediaTest) { "Use -PcampusMediaTest=true; never instrument the user's installed app." }
        check(project.layout.buildDirectory.file("generated/synthetic-media/fixture.json").get().asFile.isFile) {
            "Generate the local synthetic HLS fixture with scripts/check_native_media.py first."
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
