package io.hydrabox.core.update

import io.hydrabox.core.model.OperationState

data class ReleaseNotes(val version: String, val text: String)

sealed interface UpdateAvailability {
    data object NoUpdate : UpdateAvailability
    data class Available(val version: String) : UpdateAvailability
}

data class UpdateState(
    val availability: OperationState<UpdateAvailability> = OperationState.Idle,
    val download: OperationState<String> = OperationState.Idle,
    val changelog: List<ReleaseNotes> = emptyList(),
)
