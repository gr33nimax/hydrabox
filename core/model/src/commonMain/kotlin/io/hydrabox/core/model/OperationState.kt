package io.hydrabox.core.model

@JvmInline
value class OperationId(val value: String)

data class OperationError(val code: String)

sealed interface OperationState<out T> {
    data object Idle : OperationState<Nothing>
    data object Running : OperationState<Nothing>
    data class Succeeded<T>(val value: T) : OperationState<T>
    data class Failed(val error: OperationError) : OperationState<Nothing>
}
