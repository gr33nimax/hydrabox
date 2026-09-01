pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "HydraBox2"

include(
    ":core:model",
    ":core:contract",
    ":core:runtime",
    ":core:projection",
    ":core:storage",
    ":core:diagnostics",
    ":core:config",
    ":core:subscription",
    ":core:settings",
    ":ui:design",
    ":ui:app",
    ":platform:android",
    ":platform:desktop",
)
