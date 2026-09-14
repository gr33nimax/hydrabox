package io.hydrabox.platform.android

import io.nekohasekai.libbox.Libbox
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

internal object CoreAbi {
    // The contract with HydraCore v2: the core accepts the complete AmneziaWG 3.1
    // configuration. A core that predates it fails to parse a 3.1 profile, so an
    // older build has to be refused up front rather than at tunnel start.
    private const val expected = 2
    private val json = Json { ignoreUnknownKeys = true }

    fun isCompatible(): Boolean =
        runCatching {
            val info = json.parseToJsonElement(Libbox.hydraCoreBuildInfo()).jsonObject
            info["client_abi"]?.jsonPrimitive?.intOrNull == expected
        }.getOrDefault(false)
}
