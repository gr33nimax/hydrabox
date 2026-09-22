package io.hydrabox.ui.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ServerFlagTest {
    @Test fun `a leading flag becomes the row's own mark`() {
        val split = serverFlag("🇫🇮 AnyTLS")
        assertEquals("🇫🇮", split?.first)
        assertEquals("AnyTLS", split?.second)
    }

    @Test fun `a name that does not start with a flag is left whole`() {
        assertNull(serverFlag("AnyTLS"))
        assertNull(serverFlag(""))
        assertNull(serverFlag("FI AnyTLS"), "two latin letters are not a flag")
        assertNull(serverFlag("🇫🇮"), "a flag with no name behind it is not a server row")
    }
}
