import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Kunci tanda tangan rilis (android/key.properties, tidak ikut git).
// Tanpa file itu, build rilis memakai kunci debug.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.pos_babi_guling"
    
    // 🔥 Wajib 36 sesuai permintaan plugin
    compileSdk = 36 

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // 🔥 FIX KOTLIN DSL: Hapus kotlinOptions lama, ganti pakai format baru ini
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }

    defaultConfig {
        // ID aplikasi di HP. Jangan diubah lagi setelah dipasang di kasir,
        // kalau berubah dianggap aplikasi lain (data offline tidak terbawa).
        applicationId = "com.mengede.kasir"
        
        // Mengambil versi minimal dari Flutter (biasanya 21)
        minSdk = flutter.minSdkVersion 
        
        // Stabil di 35
        targetSdk = 35 
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }

    // 🔥 JURUS AMPUH ANTI ERROR "Illegal Char <:>" (Versi Kotlin DSL)
    androidResources {
        namespaced = false
    }
    
    // Mematikan fitur lama yang sering bikin error path
    buildFeatures {
        renderScript = false
        aidl = false
    }
}

flutter {
    source = "../.."
}