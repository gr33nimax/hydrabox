apply(from = rootProject.file("config/kmp-module.gradle"))

val secretCompileTest by configurations.creating

dependencies {
    add("commonMainApi", project(":core:model"))
    add("commonTestImplementation", "org.jetbrains.kotlin:kotlin-test")
    secretCompileTest("org.jetbrains.kotlin:kotlin-compiler-embeddable:2.2.20")
    secretCompileTest("org.jetbrains.kotlin:kotlin-stdlib:2.2.20")
}

tasks.register<JavaExec>("verifySecretCannotBeLogged") {
    group = "verification"
    dependsOn("jvmJar")
    classpath = secretCompileTest
    mainClass.set("org.jetbrains.kotlin.cli.jvm.K2JVMCompiler")
    val fixture = layout.projectDirectory.file("src/compileTest/kotlin/io/hydrabox/core/diagnostics/SecretLeak.kt")
    val output = layout.buildDirectory.dir("secret-compile-test")
    doFirst {
        args = listOf(
            "-no-stdlib", "-no-reflect",
            "-classpath", listOf(
                tasks.named<Jar>("jvmJar").get().archiveFile.get().asFile.path,
                secretCompileTest.files.first { it.name.startsWith("kotlin-stdlib") }.path,
            ).joinToString(java.io.File.pathSeparator),
            "-d", output.get().asFile.path,
            fixture.asFile.path,
        )
        isIgnoreExitValue = true
    }
    doLast {
        check(executionResult.get().exitValue != 0) { "Secret leak fixture unexpectedly compiled" }
    }
}

tasks.named("check") { dependsOn("verifySecretCannotBeLogged") }
