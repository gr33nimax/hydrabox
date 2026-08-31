apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainImplementation", project(":core:contract"))
    add("commonMainImplementation", project(":core:runtime"))
}
