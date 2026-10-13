import java.util.Properties
import java.io.FileInputStream
import java.io.File


plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile: File = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

// Production APKs remain ARM-only. Android integration tests opt into x86_64
// through ORG_GRADLE_PROJECT_agelapseCiX64 so they can run on the accelerated
// GitHub-hosted emulator without changing release packaging.
val includeCiX64 = providers.gradleProperty("agelapseCiX64").orNull == "true"
// Firebase Test Lab's physical phones are arm64. -Pagelapse.testLabAbi=arm64-v8a
// packages only that ABI, so the debug APK uploaded for each run is smaller.
val testLabAbi = providers.gradleProperty("agelapse.testLabAbi").orNull
require(testLabAbi == null || testLabAbi == "arm64-v8a") {
    "agelapse.testLabAbi only supports arm64-v8a"
}
val packagedAbis = mutableListOf("armeabi-v7a", "arm64-v8a").apply {
    if (testLabAbi != null) retainAll(listOf(testLabAbi))
    if (includeCiX64) add("x86_64")
}

android {
    namespace = "com.hugocornellier.agelapse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.hugocornellier.agelapse"
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Runs integration_test targets as instrumentation tests (Test Lab);
        // see src/androidTest.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            abiFilters += packagedAbis
        }
    }

    packaging {
        jniLibs {
            pickFirsts += packagedAbis.map { "**/$it/libc++_shared.so" }
            excludes += "**/x86/*.so"
            if (!includeCiX64) excludes += "**/x86_64/*.so"
            // Flutter's plugin adds its own ABIs back, so the filter above
            // alone still packages the 32-bit ARM libraries.
            if (testLabAbi != null) excludes += "**/armeabi-v7a/*.so"
        }
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (!storeFilePath.isNullOrBlank()) {
                storeFile = file(storeFilePath)
            }
            storePassword = keystoreProperties["storePassword"] as String?
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // The versions Flutter's integration_test plugin resolves on the app's
    // runtime classpath; AGP requires the debug and androidTest graphs to agree.
    androidTestImplementation("androidx.test:runner:1.3.0")
    androidTestImplementation("androidx.test:rules:1.2.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.3.0")
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

// Strip unused plugin assets from flutter_assets after Flutter copies them.
// These files are bundled by pub.dev plugins but never loaded at runtime
// for AgeLapse's specific configuration. See strip-savings.md for the full audit.
afterEvaluate {
    tasks.matching { it.name.startsWith("copyFlutterAssets") }.configureEach {
        doLast {
            val flutterAssetsDir = outputs.files.files
                .flatMap { it.walkTopDown().toList() }
                .firstOrNull { it.isDirectory && it.name == "flutter_assets" }
                ?: return@doLast

            // Unused TFLite models (AgeLapse only uses backCamera + heavy)
            listOf(
                "packages/face_detection_tflite/assets/models/selfie_multiclass.tflite",
                "packages/face_detection_tflite/assets/models/face_detection_full_range.tflite",
                "packages/face_detection_tflite/assets/models/face_detection_full_range_sparse.tflite",
                "packages/face_detection_tflite/assets/models/selfie_segmenter_landscape.tflite",
                "packages/face_detection_tflite/assets/models/selfie_segmenter.tflite",
                "packages/face_detection_tflite/assets/models/face_detection_front.tflite",
                "packages/face_detection_tflite/assets/models/face_detection_short_range.tflite",
                "packages/pose_detection/assets/models/pose_landmark_full.tflite",
                "packages/pose_detection/assets/models/pose_landmark_lite.tflite",
            ).forEach { rel ->
                val f = flutterAssetsDir.resolve(rel)
                if (f.exists()) {
                    logger.lifecycle("Stripping unused asset: $rel (${f.length() / 1024} KB)")
                    f.delete()
                }
            }

            // Plugin sample images, plus hand_detection models: the app only
            // reads HandDetector.modelVersion, so its models never load.
            listOf(
                "packages/pose_detection/assets/samples",
                "packages/dog_detection/assets/samples",
                "packages/animal_detection/assets/samples",
                "packages/hand_detection/assets/models",
            ).forEach { rel ->
                val d = flutterAssetsDir.resolve(rel)
                if (d.isDirectory) {
                    logger.lifecycle("Stripping unused asset dir: $rel")
                    d.deleteRecursively()
                }
            }

            // Web-only assets (never loaded on Android)
            listOf(
                "packages/flutter_avif_web",
                "packages/media_kit/assets/web",
            ).forEach { rel ->
                val d = flutterAssetsDir.resolve(rel)
                if (d.isDirectory) {
                    logger.lifecycle("Stripping web-only asset dir: $rel")
                    d.deleteRecursively()
                }
            }
            val noSleep = flutterAssetsDir.resolve("packages/wakelock_plus/assets/no_sleep.js")
            if (noSleep.exists()) noSleep.delete()
        }
    }
}
