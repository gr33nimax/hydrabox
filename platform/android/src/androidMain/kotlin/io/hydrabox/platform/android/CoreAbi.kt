package io.hydrabox.platform.android

import io.nekohasekai.libbox.Libbox
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

internal object CoreAbi {
    private const val expected = 1
    private const val pinnedLegacySource = "c7180414a98c278100f4d4985e562062826f0bfd"
    private val json = Json { ignoreUnknownKeys = true }

    fun isCompatible(): Boolean =
        runCatching {
            val info = json.parseToJsonElement(Libbox.hydraCoreBuildInfo()).jsonObject
            info["client_abi"]?.jsonPrimitive?.intOrNull == expected ||
                info["source"]
                    ?.jsonObject
                    ?.get("commit")
                    ?.jsonPrimitive
                    ?.content == pinnedLegacySource
        }.getOrDefault(false)
}
