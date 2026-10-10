package io.hydrabox.platform.android

/**
 * Reads the core again after its group notification has settled. Older cores notify about
 * probe history before committing the automatic selection, then cache that early group list.
 * A bounded follow-up reads the real selection without starting another latency sweep.
 */
internal class SelectionRefresh(
    private val schedule: (Long, () -> Unit) -> Unit,
    private val refresh: () -> Boolean,
    private val maxAttempts: Int = 8,
) {
    private val lock = Any()
    private var cycle = 0L
    private var pending = false
    private var revision = 0L

    fun request() {
        val token = synchronized(lock) {
            revision++
            if (pending) return
            pending = true
            cycle
        }
        enqueue(token, 1)
    }

    fun cancel() {
        synchronized(lock) {
            cycle++
            pending = false
        }
    }

    private fun enqueue(token: Long, attempt: Int) {
        val delay = (250L shl (attempt - 1).coerceAtMost(3))
        schedule(delay) {
            val before = synchronized(lock) {
                if (cycle != token || !pending) return@schedule
                revision
            }
            val resolved = runCatching(refresh).getOrDefault(false)
            val again = synchronized(lock) {
                if (cycle != token || !pending) return@schedule
                // A group event received while the RPC was in flight needs its own later read.
                if ((!resolved || revision != before) && attempt < maxAttempts) {
                    true
                } else {
                    pending = false
                    false
                }
            }
            if (again) enqueue(token, attempt + 1)
        }
    }
}
