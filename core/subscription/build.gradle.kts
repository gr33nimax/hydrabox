apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainApi", project(":core:contract"))
    add("commonMainApi", project(":core:diagnostics"))
    add("commonMainApi", project(":core:storage"))
    add("commonTestImplementation", "org.jetbrains.kotlin:kotlin-test")
    add("jvmTestImplementation", "app.cash.sqldelight:sqlite-driver:2.3.2")
}
