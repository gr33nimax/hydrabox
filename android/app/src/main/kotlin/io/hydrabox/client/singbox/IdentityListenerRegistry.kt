package io.hydrabox.client.singbox

import java.util.IdentityHashMap

/** Small identity-based registry; its owner supplies lifecycle synchronization. */
internal class IdentityListenerRegistry<T : Any> {
    private val values = IdentityHashMap<T, Unit>()

    fun add(value: T): Boolean = values.put(value, Unit) == null

    fun remove(value: T): Boolean = values.remove(value) != null

    fun contains(value: T): Boolean = values.containsKey(value)

    fun isEmpty(): Boolean = values.isEmpty()

    fun size(): Int = values.size

    fun snapshot(): List<T> = values.keys.toList()
}
