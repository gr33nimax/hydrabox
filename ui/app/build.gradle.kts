plugins {
    id("org.jetbrains.compose")
    kotlin("plugin.compose")
}

apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainImplementation", project(":core:runtime"))
    add("commonMainImplementation", project(":core:config"))
    add("commonMainImplementation", project(":core:subscription"))
    add("commonMainImplementation", project(":core:settings"))
    add("commonMainImplementation", project(":ui:design"))
    add("commonMainImplementation", project(":core:projection"))
    add("commonMainImplementation", project(":core:model"))
    add("commonMainImplementation", compose.runtime)
    add("commonMainImplementation", compose.ui)
    add("commonMainImplementation", compose.foundation)
    add("commonMainImplementation", compose.material3)
}
