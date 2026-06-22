import java.io.ByteArrayOutputStream

plugins {
    id("com.android.application")
}

fun gitCommit(): String {
    return try {
        val output = ByteArrayOutputStream()
        exec {
            commandLine("git", "rev-parse", "--short=12", "HEAD")
            standardOutput = output
            isIgnoreExitValue = true
        }
        output.toString().trim().ifBlank { "unknown" }
    } catch (_: Exception) {
        "unknown"
    }
}

val nebulaVersion: String = providers.gradleProperty("nebulaVersion").get()
val nebulaVersionCode: Int = providers.gradleProperty("nebulaVersionCode").get().toInt()
val nebulaCoreProtocolVersion: String = providers.gradleProperty("nebulaCoreProtocolVersion").get()
val nebulaGitCommit: String = gitCommit()

android {
    namespace = "io.droidspaces.nebula"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.droidspaces.nebula"
        minSdk = 26
        targetSdk = 36
        versionCode = nebulaVersionCode
        versionName = nebulaVersion
        buildConfigField("String", "NEBULA_APP_VERSION", "\"$nebulaVersion\"")
        buildConfigField("String", "NEBULA_MODULE_VERSION", "\"$nebulaVersion\"")
        buildConfigField("int", "NEBULA_CORE_PROTOCOL_VERSION", nebulaCoreProtocolVersion)
        buildConfigField("String", "NEBULA_GIT_COMMIT", "\"$nebulaGitCommit\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
        debug {
            isDebuggable = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }
}

tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
    options.compilerArgs.add("-Xlint:deprecation")
}
