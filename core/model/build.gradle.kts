import org.gradle.api.artifacts.ProjectDependency

apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonTestImplementation", "org.jetbrains.kotlin:kotlin-test")
}

tasks.register("verifyModelHasNoDependencies") {
    group = "verification"
    description = "Ensures :core:model remains a dependency-free foundation module."
    doLast {
        val moduleDependencies = configurations
            .filter { it.name.startsWith("commonMain") || it.name.startsWith("androidMain") || it.name.startsWith("jvmMain") }
            .flatMap { it.dependencies }
            .filterIsInstance<ProjectDependency>()
        check(moduleDependencies.isEmpty()) { ":core:model must not depend on another module" }
    }
}

tasks.named("check") { dependsOn("verifyModelHasNoDependencies") }
