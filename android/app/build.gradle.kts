import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localSigningProps = Properties()
val localSigningFile = rootProject.file("local-signing.properties")
val hasLocalSigning = localSigningFile.exists()

if (hasLocalSigning) {
    localSigningFile.inputStream().use { localSigningProps.load(it) }
}

android {
    namespace = "com.colourswift.safehaven"
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
        applicationId = "com.colourswift.safehaven"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasLocalSigning) {
                keyAlias = localSigningProps["keyAlias"] as String
                keyPassword = localSigningProps["keyPassword"] as String
                storeFile = file(localSigningProps["storeFile"] as String)
                storePassword = localSigningProps["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasLocalSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}

flutter {
    source = "../.."
}
