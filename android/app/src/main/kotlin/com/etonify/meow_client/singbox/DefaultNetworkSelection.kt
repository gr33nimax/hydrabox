package com.etonify.meow_client.singbox

internal data class DefaultNetworkCandidate<T>(
    val value: T,
    val isActive: Boolean,
    val isValidated: Boolean,
    val hasUsableInterface: Boolean,
    val score: Int,
)

/**
 * Keeps the current usable physical network when Android reports the VPN itself as
 * active and temporarily removes VALIDATED from its underlying network.
 */
internal fun <T> selectDefaultNetworkCandidate(
    candidates: List<DefaultNetworkCandidate<T>>,
    current: T?,
): DefaultNetworkCandidate<T>? {
    return candidates
        .filter { it.isValidated }
        .maxByOrNull { it.score }
        ?: candidates
            .filter { it.isActive }
            .maxByOrNull { it.score }
        ?: candidates
            .firstOrNull { it.value == current && it.hasUsableInterface }
        ?: candidates
            .filter { it.hasUsableInterface }
            .maxByOrNull { it.score }
}
