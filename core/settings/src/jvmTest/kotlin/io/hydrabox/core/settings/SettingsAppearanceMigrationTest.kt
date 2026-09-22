package io.hydrabox.core.settings

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/**
 * What the old appearance setting becomes now that there is no palette of our own.
 *
 * The flag that used to mean "take the phone's colours" is gone, and `SYSTEM` means exactly that
 * today. So the migration is not a rename of the value: a person who had the phone's colours under
 * a fixed brightness has to end up on `SYSTEM`, or the update would quietly hand them a different
 * palette than the one they chose.
 */
class SettingsAppearanceMigrationTest {
    private val codec = SettingsCodec()

    @Test fun `a person who had the phone's own colours keeps them, whatever brightness that was`() {
        assertEquals(
            ThemeMode.SYSTEM,
            codec.decode(mapOf("dynamic_colour" to "1", "theme_mode" to "light")).themeMode,
        )
        assertEquals(
            ThemeMode.SYSTEM,
            codec.decode(mapOf("dynamic_colour" to "1", "theme_mode" to "dark")).themeMode,
        )
    }

    @Test fun `a person who chose a brightness keeps it as a fixed scheme`() {
        assertEquals(ThemeMode.LIGHT, codec.decode(mapOf("theme_mode" to "light")).themeMode)
        assertEquals(ThemeMode.DARK, codec.decode(mapOf("theme_mode" to "dark")).themeMode)
        assertEquals(ThemeMode.SYSTEM, codec.decode(mapOf("theme_mode" to "system")).themeMode)
    }

    @Test fun `settings written before the flag existed are read as they were`() {
        assertEquals(ThemeMode.SYSTEM, codec.decode(emptyMap()).themeMode)
    }

    @Test fun `the flag is never written back`() {
        val migrated = codec.decode(mapOf("dynamic_colour" to "1", "theme_mode" to "dark"))
        assertFalse(codec.encode(migrated).containsKey("dynamic_colour"))
        // Written, read back, and still the same answer: the migration happens once and then the
        // setting is just `SYSTEM`.
        assertEquals(ThemeMode.SYSTEM, codec.decode(codec.encode(migrated)).themeMode)
    }
}
