plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
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
        applicationId = "com.example.pos_babi_guling"
        
        // Mengambil versi minimal dari Flutter (biasanya 21)
        minSdk = flutter.minSdkVersion 
        
        // Stabil di 35
        targetSdk = 35 
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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