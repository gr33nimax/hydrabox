package io.hydrabox.client.singbox

internal data class DefaultNetworkCandidate<T>(
    val value: T,
    val isActive: Boolean,
    val isValidated: Boolean,
    val hasUsableInterface: Boolean,
    val score: Int,
)

/**
 * Keeps the current usable physical network when Android reports the VPN itself as
 * active and temporarily removes VALIDATED from its underlying network. When a
 * callback identifies a validated physical handover target, that callback
 * network wins and remains preferred over a higher-scoring stale transport.
 */
internal fun <T> selectDefaultNetworkCandidate(
    candidates: List<DefaultNetworkCandidate<T>>,
    current: T?,
    preferred: T? = null,
): DefaultNetworkCandidate<T>? {
    val usablePreferred = candidates.firstOrNull {
        it.value == preferred && it.isValidated && it.hasUsableInterface
    }
    val usableCurrent = candidates.firstOrNull {
        it.value == current && it.isValidated && it.hasUsableInterface
    }
    return usablePreferred
        ?: usableCurrent
        ?: candidates
        .filter { it.isValidated }
        .maxByOrNull { it.score }
        ?: candidates
            .filter { it.isActive }
            .maxByOrNull { it.score }
        ?: candidates
            .firstOrNull { it.value == preferred && it.hasUsableInterface }
        ?: candidates
            .firstOrNull { it.value == current && it.hasUsableInterface }
        ?: candidates
            .filter { it.hasUsableInterface }
            .maxByOrNull { it.score }
}
