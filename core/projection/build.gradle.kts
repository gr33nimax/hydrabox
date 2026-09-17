apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainApi", project(":core:contract"))
    add("commonMainApi", project(":core:model"))
    // Exposed through the projection's own vocabulary: the update summary carries the updater's
    // reasons, so a consumer of this module needs them on its compile classpath.
    add("commonMainApi", project(":core:update"))
    add("commonTestImplementation", "org.jetbrains.kotlin:kotlin-test")
}
