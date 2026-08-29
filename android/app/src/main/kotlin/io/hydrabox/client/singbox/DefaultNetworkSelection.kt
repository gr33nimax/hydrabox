package io.hydrabox.client.singbox

internal data class DefaultNetworkCandidate<T>(
    val value: T,
    val isValidated: Boolean,
    val hasUsableInterface: Boolean,
    val score: Int,
)

/**
 * Selects an Android-validated physical network with a usable interface when available.
 * Falls back to an unvalidated physical network with a usable interface in restricted
 * network environments (such as whitelist captive environments where validation probes fail).
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
    val bestValidated = candidates
        .filter { it.isValidated && it.hasUsableInterface }
        .maxByOrNull { it.score }

    if (usablePreferred != null) return usablePreferred
    if (usableCurrent != null) return usableCurrent
    if (bestValidated != null) return bestValidated

    val fallbackPreferred = candidates.firstOrNull {
        it.value == preferred && it.hasUsableInterface
    }
    val fallbackCurrent = candidates.firstOrNull {
        it.value == current && it.hasUsableInterface
    }
    return fallbackPreferred
        ?: fallbackCurrent
        ?: candidates
            .filter { it.hasUsableInterface }
            .maxByOrNull { it.score }
}
