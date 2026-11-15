plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "de.drdothouse.ohrregal.tv"
    compileSdk = 35
    defaultConfig {
        applicationId = "de.drdothouse.ohrregal.tv"
        minSdk = 22
        targetSdk = 35
        // Versionsnummer kommt im GitHub-Ablauf aus der Laufnummer.
        versionCode = (System.getenv("VERSION_CODE") ?: "1").toInt()
        versionName = "0.1." + (System.getenv("VERSION_CODE") ?: "0")
    }
    signingConfigs {
        create("release") {
            // Schlüssel aus den GitHub-Secrets; ohne sie wird mit dem Debug-Schlüssel signiert.
            val datei = System.getenv("TV_KEYSTORE_DATEI")
            if (datei != null) {
                storeFile = file(datei)
                storePassword = System.getenv("TV_KEYSTORE_PASSWORT")
                keyAlias = "ohrregal"
                keyPassword = System.getenv("TV_KEYSTORE_PASSWORT")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = if (System.getenv("TV_KEYSTORE_DATEI") != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}

dependencies {
    val compose = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(compose)
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.tv:tv-material:1.0.0")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
    implementation("androidx.media3:media3-session:1.5.1")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
