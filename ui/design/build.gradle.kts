plugins {
    id("org.jetbrains.compose")
    kotlin("plugin.compose")
}

apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainImplementation", compose.runtime)
    add("commonMainImplementation", compose.ui)
    add("commonMainImplementation", compose.foundation)
    add("commonMainImplementation", compose.material3)
    add("commonTestImplementation", "org.jetbrains.kotlin:kotlin-test")
}
