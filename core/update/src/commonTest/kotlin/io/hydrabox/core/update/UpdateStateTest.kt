package io.hydrabox.core.update

import io.hydrabox.core.model.OperationError
import io.hydrabox.core.model.OperationState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class UpdateStateTest {
    @Test fun `update state represents no update available downloading and error`() {
        assertIs<OperationState.Succeeded<UpdateAvailability>>(UpdateState(availability = OperationState.Succeeded(UpdateAvailability.NoUpdate)).availability)
        assertEquals("2.0.1", assertIs<UpdateAvailability.Available>(assertIs<OperationState.Succeeded<UpdateAvailability>>(UpdateState(availability = OperationState.Succeeded(UpdateAvailability.Available("2.0.1"))).availability).value).version)
        assertIs<OperationState.Running>(UpdateState(download = OperationState.Running).download)
        assertEquals("network", assertIs<OperationState.Failed>(UpdateState(availability = OperationState.Failed(OperationError("network"))).availability).error.code)
    }
}
