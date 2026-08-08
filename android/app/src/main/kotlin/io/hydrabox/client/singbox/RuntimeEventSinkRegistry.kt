package io.hydrabox.client.singbox

/**
 * Owns the currently attached Flutter event sink.
 *
 * A foreground service can outlive the Flutter activity. On some Android
 * builds the old engine delivers onCancel after a replacement engine has
 * already subscribed. Registration tokens keep that stale callback from
 * detaching the new UI.
 */
internal class RuntimeEventSinkRegistry<T> {
    private var nextRegistration = 0L
    private var activeRegistration = 0L
    private var activeValue: T? = null

    @Synchronized
    fun register(value: T): Long {
        nextRegistration++
        activeRegistration = nextRegistration
        activeValue = value
        return activeRegistration
    }

    @Synchronized
    fun clear(registration: Long): Boolean {
        if (registration == 0L || registration != activeRegistration) {
            return false
        }
        activeRegistration = 0L
        activeValue = null
        return true
    }

    @Synchronized
    fun current(): T? = activeValue

    @Synchronized
    fun hasActiveRegistration(): Boolean = activeRegistration != 0L

    @Synchronized
    fun canControl(registration: Long): Boolean =
        if (registration == 0L) {
            activeRegistration == 0L
        } else {
            registration == activeRegistration
        }
}
