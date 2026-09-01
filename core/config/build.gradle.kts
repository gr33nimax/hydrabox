apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainApi", project(":core:contract"))
    add("commonMainApi", project(":core:subscription"))
    add("commonMainImplementation", "org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    add("commonTestImplementation", "org.jetbrains.kotlin:kotlin-test")
}
