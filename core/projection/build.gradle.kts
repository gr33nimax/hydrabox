apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainApi", project(":core:contract"))
    add("commonTestImplementation", "org.jetbrains.kotlin:kotlin-test")
}
