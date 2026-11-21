import java.util.Base64

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Opt-in, isolated on-device performance fixture. Its Dart entry point uses
// synthetic repositories; normal builds keep their original application ID.
val dartDefines = providers.gradleProperty("dart-defines").orNull.orEmpty()
    .split(",").mapNotNull { encoded ->
        runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }.getOrNull()
    }
val performanceHarness = "FOUNDI_PERF_HARNESS=true" in dartDefines
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
fun checkReleaseInputs() {
    if (performanceHarness || "USE_FIREBASE_EMULATORS=true" in dartDefines ||
        dartDefines.any { it.substringBefore("=").startsWith("FIREBASE_EMULATOR_") ||
            it.substringBefore("=") in listOf("FIREBASE_AUTH_EMULATOR_PORT", "FIRESTORE_EMULATOR_PORT", "FUNCTIONS_EMULATOR_PORT") }) {
        throw GradleException("Emulator and performance configurations are forbidden in a Foundi release.")
    }
    val target = providers.gradleProperty("target").orNull
    if (target != null && rootProject.projectDir.parentFile.resolve(target).canonicalFile != rootProject.projectDir.parentFile.resolve("lib/main.dart").canonicalFile) {
        throw GradleException("Foundi releases must use lib/main.dart, never a test entry point.")
    }
}
if (releaseRequested) checkReleaseInputs()
tasks.matching { it.name.endsWith("GoogleServices") }.configureEach {
    if (performanceHarness) enabled = false
}

// Signing material stays outside the repository. Release tasks fail closed
// without a dedicated upload key; debug and profile builds remain available.
val uploadVariableNames = listOf(
    "FOUNDI_UPLOAD_KEYSTORE", "FOUNDI_UPLOAD_STORE_PASSWORD",
    "FOUNDI_UPLOAD_KEY_ALIAS", "FOUNDI_UPLOAD_KEY_PASSWORD"
)
val uploadSigningValues = uploadVariableNames.map { providers.environmentVariable(it).orNull }
val uploadSigningConfigured = uploadSigningValues.all { !it.isNullOrBlank() }
if (releaseRequested && !uploadSigningConfigured) {
    throw GradleException("A dedicated external upload key is required for a Foundi release (FOUNDI_UPLOAD_*).")
}
if (uploadSigningValues.any { !it.isNullOrBlank() } && !uploadSigningConfigured) {
    throw GradleException("Upload signing requires all four FOUNDI_UPLOAD_* environment variables.")
}
if (uploadSigningConfigured &&
    uploadSigningValues[2].equals("androiddebugkey", ignoreCase = true)) {
    throw GradleException("The Android debug key must not sign a Foundi release.")
}
if (uploadSigningConfigured) {
    val uploadFile = file(uploadSigningValues[0]!!).canonicalFile
    if (!uploadFile.isFile || uploadFile.toPath().startsWith(rootProject.projectDir.parentFile.canonicalFile.toPath())) {
        throw GradleException("The upload keystore must exist outside the Foundi repository.")
    }
}
// Aggregate tasks such as `assemble` must obey the same checks as bundleRelease.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("release", ignoreCase = true) }) {
        checkReleaseInputs()
        if (!uploadSigningConfigured) {
            throw GradleException("A dedicated external upload key is required for a Foundi release (FOUNDI_UPLOAD_*).")
        }
    }
}

android {
    namespace = "com.foundi.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent Android application ID approved for the Google Play app.
        applicationId = "com.foundi.app"
        if (performanceHarness) applicationIdSuffix = ".performance"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (uploadSigningConfigured) {
            create("upload") {
                storeType = "JKS"
                storeFile = file(uploadSigningValues[0]!!)
                storePassword = uploadSigningValues[1]
                keyAlias = uploadSigningValues[2]
                keyPassword = uploadSigningValues[3]
            }
        }
    }

    buildTypes {
        release {
            isDebuggable = false
            signingConfig = if (uploadSigningConfigured) signingConfigs.getByName("upload") else null
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
