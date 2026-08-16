package io.hydrabox.client.singbox

internal data class DefaultNetworkCandidate<T>(
    val value: T,
    val isActive: Boolean,
    val isValidated: Boolean,
    val hasUsableInterface: Boolean,
    val score: Int,
)

/** Selects only an Android-validated physical network with a usable interface. */
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
        .filter { it.isValidated && it.hasUsableInterface }
        .maxByOrNull { it.score }
}
