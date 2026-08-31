apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainImplementation", project(":core:runtime"))
    add("commonMainImplementation", project(":core:config"))
    add("commonMainImplementation", project(":core:subscription"))
    add("commonMainImplementation", project(":core:settings"))
    add("commonMainImplementation", project(":ui:design"))
}
