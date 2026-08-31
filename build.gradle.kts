import org.gradle.api.artifacts.ProjectDependency

plugins {
    kotlin("multiplatform") version "2.2.20" apply false
    id("com.android.library") version "8.11.1" apply false
}

val forbiddenCommonMainTokens = listOf(
    "android.",
    "process death",
    "processDeath",
    "ConnectivityManager",
    "NetworkStrategyDefault",
    "libbox",
    "doze",
    "wake",
    "LOST_GRACE",
)

tasks.register("verifyCommonMainBoundaries") {
    group = "verification"
    description = "Rejects platform-specific runtime APIs in commonMain."
    doLast {
        val violations = subprojects.flatMap { project ->
            project.fileTree("src/commonMain") {
                include("**/*.kt")
            }.files.flatMap { file ->
                forbiddenCommonMainTokens.filter { token -> file.readText().contains(token, ignoreCase = true) }
                    .map { token -> "${file.relativeTo(rootDir)} contains forbidden token '$token'" }
            }
        }
        check(violations.isEmpty()) { violations.joinToString("\n") }
    }
}

subprojects {
    afterEvaluate {
        if (path.startsWith(":core:") && configurations.any { configuration ->
                configuration.dependencies.any { dependency ->
                    dependency is ProjectDependency && dependency.path.startsWith(":platform:")
                }
            }) {
            throw GradleException("$path must not depend on a platform module")
        }
    }

    tasks.matching { it.name.startsWith("compile") && it.name.contains("Kotlin") }
        .configureEach { dependsOn(rootProject.tasks.named("verifyCommonMainBoundaries")) }
}
