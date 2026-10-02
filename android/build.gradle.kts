allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 🔥 KITA KEMBALIKAN RUTE FOLDERNYA KE SINI 🔥
// Supaya alat 'flutter run' bisa menemukan file .apk yang sudah jadi
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // 🔥 INI JUGA DIKEMBALIKAN 🔥
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    project.afterEvaluate {
        val androidExt = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (androidExt != null) {
            
            // Paksa semua plugin pakai SDK 36
            androidExt.compileSdkVersion(36)

            // Fix Namespace Otomatis
            if (androidExt.namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val manifestXml = manifestFile.readText()
                    val packageMatch = Regex("""package\s*=\s*"([^"]+)"""").find(manifestXml)
                    val packageName = packageMatch?.groupValues?.get(1)
                    if (packageName != null) {
                        androidExt.namespace = packageName
                        println("✅ Auto-Fixed Namespace for ${project.name}: $packageName")
                    }
                }
            }

            // Paksa Java 17
            androidExt.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }

    // Paksa Kotlin 17
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }

    // Paksa Java Compile 17
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}