plugins {
    id("app.cash.sqldelight")
}

apply(from = rootProject.file("config/kmp-module.gradle"))

dependencies {
    add("commonMainApi", project(":core:diagnostics"))
    add("commonMainApi", "app.cash.sqldelight:runtime:2.3.2")
    add("androidMainImplementation", "app.cash.sqldelight:android-driver:2.3.2")
    add("jvmMainImplementation", "app.cash.sqldelight:sqlite-driver:2.3.2")
    add("jvmMainImplementation", "net.java.dev.jna:jna-platform:5.18.1")
    add("commonTestImplementation", "org.jetbrains.kotlin:kotlin-test")
}

sqldelight {
    databases {
        create("StorageDatabase") {
            packageName.set("io.hydrabox.core.storage")
            deriveSchemaFromMigrations.set(true)
            schemaOutputDirectory.set(file("src/commonMain/sqldelight/databases"))
            verifyMigrations.set(true)
        }
    }
}

tasks.named("check") { dependsOn("verifySqlDelightMigration") }
