plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.inodoro_inteligente"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.inodoro_inteligente"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

androidComponents {
    onVariants { variant ->
        if (variant.buildType != "release") return@onVariants

        val capitalizedName = variant.name.replaceFirstChar { it.uppercase() }
        val renameTask = tasks.register("renameApk$capitalizedName") {
            doLast {
                val newFileName = "inodoro-smart.apk"
                listOf(
                    "outputs/apk/${variant.name}",
                    "outputs/flutter-apk",
                ).forEach { dir ->
                    val apkDir = layout.buildDirectory.dir(dir).get().asFile
                    if (!apkDir.exists()) return@forEach
                    apkDir.listFiles()
                        ?.filter { it.name == "app-release.apk" }
                        ?.forEach { apk ->
                            val target = File(apk.parentFile, newFileName)
                            apk.copyTo(target, overwrite = true)
                            println("APK renombrado: ${apk.name} -> $newFileName")
                        }
                }
            }
        }

        project.afterEvaluate {
            tasks.findByName("assemble$capitalizedName")?.finalizedBy(renameTask)
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
