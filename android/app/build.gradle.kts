import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val privateSigningFile = rootProject.file("key.properties")
val privateSigning = Properties().apply {
    if (privateSigningFile.exists()) privateSigningFile.inputStream().use { load(it) }
}

android {
    namespace = "app.sliptrack.sliptrack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.sliptrack.sliptrack"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (privateSigningFile.exists()) {
            create("privateRelease") {
                storeFile = rootProject.file(privateSigning.getProperty("storeFile"))
                storePassword = privateSigning.getProperty("storePassword")
                keyAlias = privateSigning.getProperty("keyAlias")
                keyPassword = privateSigning.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            if (privateSigningFile.exists()) signingConfig = signingConfigs.getByName("privateRelease")
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

dependencies {
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    implementation("androidx.activity:activity-ktx:1.12.4")
}
