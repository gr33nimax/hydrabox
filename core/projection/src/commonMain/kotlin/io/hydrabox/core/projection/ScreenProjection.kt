package io.hydrabox.core.projection

import io.hydrabox.core.contract.RuntimeSnapshot
import io.hydrabox.core.contract.RuntimeState

enum class ScreenPhase { DISCONNECTED, CONNECTING, CONNECTED, DISCONNECTING, ERROR }

data class ScreenState(val phase: ScreenPhase, val canStart: Boolean, val canStop: Boolean, val canRetry: Boolean, val errorCode: String?)

object ScreenProjection {
    fun project(snapshot: RuntimeSnapshot): ScreenState = when (snapshot.state) {
        RuntimeState.STOPPED -> ScreenState(ScreenPhase.DISCONNECTED, true, false, false, null)
        RuntimeState.STARTING, RuntimeState.RECOVERING -> ScreenState(ScreenPhase.CONNECTING, false, true, false, null)
        RuntimeState.RUNNING -> ScreenState(ScreenPhase.CONNECTED, false, true, false, null)
        RuntimeState.STOPPING -> ScreenState(ScreenPhase.DISCONNECTING, false, false, false, null)
        RuntimeState.FAILED -> ScreenState(ScreenPhase.ERROR, true, false, snapshot.lastFailure?.retryable == true, snapshot.lastFailure?.code?.code)
    }
}
