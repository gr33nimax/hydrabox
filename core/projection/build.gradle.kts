apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainApi", project(":core:contract"))
    add("commonMainApi", project(":core:model"))
    add("commonTestImplementation", "org.jetbrains.kotlin:kotlin-test")
}
