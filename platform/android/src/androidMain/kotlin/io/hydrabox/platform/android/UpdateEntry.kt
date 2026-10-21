package io.hydrabox.platform.android

/** Configuration recreation is the same visit; a return from the background is a new one. */
internal class UpdateEntry {
    private var active = false
    fun enter(): Boolean = (!active).also { active = true }
    fun leave(changingConfigurations: Boolean) {
        if (!changingConfigurations) active = false
    }
}

class UpdateEntryState : androidx.lifecycle.ViewModel() {
    internal val entry = UpdateEntry()
}
