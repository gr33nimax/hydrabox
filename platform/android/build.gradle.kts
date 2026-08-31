import com.android.build.api.dsl.LibraryExtension

apply(from = rootProject.file("config/kmp-module.gradle"))

val libboxAar = file("libs/libbox.aar")
val provenance = file("libs/libbox.provenance.json")
val provenanceText = provenance.readText()
val hydraCoreVersion = Regex("""\"version\"\s*:\s*\"([^\"]+)\"""")
    .find(provenanceText)?.groupValues?.get(1)
    ?: error("libbox provenance has no distribution version")
val hydraCoreCommit = Regex("""\"commit\"\s*:\s*\"([0-9a-f]{40})\"""")
    .find(provenanceText)?.groupValues?.get(1)
    ?: error("libbox provenance has no source commit")
val libboxSha256 = Regex("""\"sha256\"\s*:\s*\"([0-9a-f]{64})\"""")
    .find(provenanceText)?.groupValues?.get(1)
    ?: error("libbox provenance has no AAR digest")

extensions.configure<LibraryExtension> {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { buildConfig = true }
    defaultConfig { buildConfigField("String", "HYDRACORE_VERSION", "\"$hydraCoreVersion\"") }
}

dependencies {
    add("commonMainImplementation", project(":core:contract"))
    add("commonMainImplementation", project(":core:runtime"))
    add("androidMainImplementation", files(libboxAar))
}

tasks.register("verifyLibboxProvenance") {
    group = "verification"
    description = "Verifies the hydrated libbox AAR against its published provenance and gitlink."
    inputs.files(provenance, libboxAar)
    doLast {
        check(libboxAar.isFile) { "Missing ${libboxAar.path}; hydrate the published libbox release." }
        val gitlink = providers.exec {
            workingDir(rootProject.file("hydracore"))
            commandLine("git", "rev-parse", "HEAD")
        }.standardOutput.asText.get().trim()
        check(gitlink == hydraCoreCommit) { "HydraCore gitlink does not match libbox provenance" }
        val actual = java.security.MessageDigest.getInstance("SHA-256")
            .digest(libboxAar.readBytes()).joinToString("") { "%02x".format(it.toInt() and 0xff) }
        check(actual == libboxSha256) { "libbox AAR does not match published provenance" }
    }
}
