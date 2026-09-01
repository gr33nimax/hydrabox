import org.gradle.api.artifacts.ProjectDependency
import org.gradle.api.artifacts.ExternalModuleDependency

plugins {
    kotlin("multiplatform") version "2.2.20" apply false
    kotlin("android") version "2.2.20" apply false
    id("com.android.library") version "8.11.1" apply false
    id("com.android.application") version "8.11.1" apply false
    id("app.cash.sqldelight") version "2.3.2" apply false
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

val forbiddenCommonMainJvmApi = Regex("""\b(?:java|javax|kotlin\.jvm)\.""")
val appleCompatibleCommonMainDependencies = setOf(
    "org.jetbrains.kotlin:kotlin-stdlib",
    "app.cash.sqldelight:runtime",
)

tasks.register("verifyCommonMainBoundaries") {
    group = "verification"
    description = "Rejects platform APIs and unverified external dependencies in commonMain."
    doLast {
        val sourceViolations = subprojects.flatMap { project ->
            project.fileTree("src/commonMain") {
                include("**/*.kt")
            }.files.flatMap { file ->
                val text = file.readText()
                forbiddenCommonMainTokens.filter { token -> text.contains(token, ignoreCase = true) }
                    .map { token -> "${file.relativeTo(rootDir)} contains forbidden token '$token'" }
                    .plus(if (forbiddenCommonMainJvmApi.containsMatchIn(text)) {
                        listOf("${file.relativeTo(rootDir)} uses a JVM-only API in commonMain")
                    } else {
                        emptyList()
                    })
            }
        }
        val dependencyViolations = subprojects.flatMap { project ->
            project.configurations.matching { it.name.startsWith("commonMain") }.flatMap { configuration ->
                configuration.dependencies.filterIsInstance<ExternalModuleDependency>()
                    .filter { "${it.group}:${it.name}" !in appleCompatibleCommonMainDependencies }
                    .map { dependency ->
                        "$project commonMain dependency ${dependency.group}:${dependency.name} is not verified for Apple targets"
                    }
            }
        }
        check((sourceViolations + dependencyViolations).isEmpty()) {
            (sourceViolations + dependencyViolations).joinToString("\n")
        }
    }
}

tasks.register("ciCheck") {
    group = "verification"
    description = "Runs every module's verification tasks for CI."
    dependsOn("verifyCommonMainBoundaries")
    dependsOn(allprojects.filter { it != rootProject && it.childProjects.isEmpty() }
        .map { "${it.path}:check" })
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
