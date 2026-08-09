import java.security.MessageDigest
import java.util.Properties
import org.gradle.api.GradleException
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("androidx.baselineprofile")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}
val allowDebugReleaseSigning =
    System.getenv("HYDRABOX_ALLOW_DEBUG_RELEASE_SIGNING")?.equals("true", ignoreCase = true) == true
val libboxAar = file("libs/libbox.aar")
val libboxChecksum = file("libs/libbox.sha256")

val verifyPinnedLibbox by tasks.registering {
    group = "verification"
    description = "Verifies the hydrated sing-box extended Android archive."
    inputs.files(libboxAar, libboxChecksum).optional()

    doLast {
        val hydrationCommand =
            "Run `python -B scripts/fetch_libbox.py` from the repository root."
        if (!libboxAar.isFile) {
            throw GradleException("Missing ${libboxAar.path}. $hydrationCommand")
        }
        if (!libboxChecksum.isFile) {
            throw GradleException("Missing ${libboxChecksum.path}. $hydrationCommand")
        }

        val checksumMatch =
            Regex("""^([0-9a-fA-F]{64})\s+\*?libbox\.aar$""")
                .matchEntire(libboxChecksum.readText().trim())
                ?: throw GradleException(
                    "Invalid ${libboxChecksum.path}. $hydrationCommand",
                )
        val expectedChecksum = checksumMatch.groupValues[1].lowercase()
        val digest = MessageDigest.getInstance("SHA-256")
        libboxAar.inputStream().buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        val actualChecksum =
            digest.digest().joinToString("") { byte ->
                "%02x".format(byte.toInt() and 0xff)
            }
        if (actualChecksum != expectedChecksum) {
            throw GradleException(
                "libbox.aar SHA-256 mismatch: expected $expectedChecksum, " +
                    "got $actualChecksum. $hydrationCommand",
            )
        }
    }
}

android {
    namespace = "io.hydrabox.client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.hydrabox.client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                val storeFilePath = keyProperties.getProperty("storeFile")
                check(!storeFilePath.isNullOrBlank()) {
                    "storeFile is missing in android/key.properties"
                }
                storeFile = rootProject.file(storeFilePath)
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (keyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugReleaseSigning) {
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    lint {
        // Flutter regenerates android/local.properties with valid Windows paths
        // before Gradle runs, while Android lint incorrectly flags that file.
        disable += "PropertyEscape"
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

gradle.taskGraph.whenReady {
    val releaseTaskRequested = allTasks.any { task ->
        task.project == project && task.name.contains("release", ignoreCase = true)
    }
    if (releaseTaskRequested && !keyPropertiesFile.exists() && !allowDebugReleaseSigning) {
        throw GradleException(
            "Release signing requires android/key.properties. " +
                "Set HYDRABOX_ALLOW_DEBUG_RELEASE_SIGNING=true only for local release testing.",
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(files("libs/libbox.aar"))
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")
    baselineProfile(project(":benchmark"))
    testImplementation("junit:junit:4.13.2")
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(verifyPinnedLibbox)
}
