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
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            pickFirsts += setOf(
                "**/armeabi-v7a/libc++_shared.so",
                "**/arm64-v8a/libc++_shared.so",
            )
            excludes += setOf("**/x86/*.so", "**/x86_64/*.so")
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
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
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
            ).forEach { rel ->
                val f = flutterAssetsDir.resolve(rel)
                if (f.exists()) {
                    logger.lifecycle("Stripping unused asset: $rel (${f.length() / 1024} KB)")
                    f.delete()
                }
            }

            // Plugin sample images
            listOf(
                "packages/pose_detection/assets/samples",
                "packages/dog_detection/assets/samples",
                "packages/animal_detection/assets/samples",
            ).forEach { rel ->
                val d = flutterAssetsDir.resolve(rel)
                if (d.isDirectory) {
                    logger.lifecycle("Stripping unused sample dir: $rel")
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
