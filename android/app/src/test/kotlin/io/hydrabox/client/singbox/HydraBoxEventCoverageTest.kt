package io.hydrabox.client.singbox

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HydraBoxEventCoverageTest {
    private val sources = listOf("runtime/CoreRuntimeService.kt", "singbox/RuntimeSession.kt", "singbox/HydraBoxDefaultNetworkMonitor.kt", "singbox/HydraBoxVpnService.kt").associateWith(::source)

    @Test fun `required events are present`() {
        val text = sources.values.joinToString("\n")
        setOf("CONNECT", "START", "NETWORK", "READY", "REBIND", "RECOVERY", "STOP", "EPOCH").forEach { assertTrue("missing $it", Regex("""event\(\s*"$it""").containsMatchIn(text)) }
    }

    @Test fun `event literals are safe and formatting is outside calls`() {
        calls().forEach { (path, call) ->
            assertFalse("sensitive literal in $path", Regex(""""[^"]*(http|join_link|joinLink|token|password|secret|cookie|captcha_sid|success_token)[^"]*""", RegexOption.IGNORE_CASE).containsMatchIn(call))
            assertFalse("formatting in event call: $path", listOf("joinToString", "String.format", "%02x").any(call::contains))
        }
    }

    @Test fun `prof follows file matrix`() {
        val core = calls("runtime/CoreRuntimeService.kt").map { it.second }.toList()
        assertTrue("core has no events", core.isNotEmpty())
        assertTrue("core event missing prof", core.all { "\"prof\"" in it })
        sources.keys.filterNot { it == "runtime/CoreRuntimeService.kt" }.forEach { path -> assertTrue("prof outside core: $path", calls(path).none { "\"prof\"" in it.second }) }
        assertTrue("activeConfigSha256 outside core", mainSources().filterNot { it.first.normalizedPath().endsWith("runtime/CoreRuntimeService.kt") }.none { "activeConfigSha256" in it.second })
    }

    @Test fun `callback timestamp has exactly four callback writers`() {
        val source = sources.getValue("singbox/HydraBoxDefaultNetworkMonitor.kt")
        val callbackStart = source.indexOf("private val callback = object")
        val callbackEnd = source.indexOf("\n    fun start()", callbackStart)
        assertTrue("callback object not found", callbackStart >= 0 && callbackEnd > callbackStart)
        val callback = source.substring(callbackStart, callbackEnd)
        assertTrue("timestamp writers outside callback", Regex("""lastAndroidCallbackElapsedMs\.set\(""").findAll(source).count() == 4)
        assertTrue("callback must contain all timestamp writers", Regex("""lastAndroidCallbackElapsedMs\.set\(""").findAll(callback).count() == 4)
        assertTrue("timestamp used outside monitor", mainSources().filterNot { it.first.normalizedPath().endsWith("singbox/HydraBoxDefaultNetworkMonitor.kt") }.none { "lastAndroidCallbackElapsedMs" in it.second })
        assertTrue("SystemClock.elapsedRealtime()" in source)
    }

    private fun calls(path: String? = null): Sequence<Pair<String, String>> = sources.asSequence().filter { path == null || it.key == path }.flatMap { (file, text) -> Regex("""event\([\s\S]*?\n\s*\)""").findAll(text).asSequence().map { file to it.value } }
    private fun mainSources(): Sequence<Pair<String, String>> = sourceRoot().walkTopDown().filter { it.extension == "kt" }.map { it.path to it.readText() }
    private fun source(path: String): String = File(sourceRoot(), "io/hydrabox/client/$path").readText()
    private fun String.normalizedPath(): String = replace('\\', '/')
    private fun sourceRoot(): File { var root = File(requireNotNull(System.getProperty("user.dir"))); while (!File(root, "android/app/src/main/kotlin").isDirectory) root = root.parentFile ?: error("root not found"); return File(root, "android/app/src/main/kotlin") }
}
