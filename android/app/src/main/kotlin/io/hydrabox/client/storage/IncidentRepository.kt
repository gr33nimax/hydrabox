package io.hydrabox.client.storage

import java.util.UUID

class IncidentRepository(
    private val dao: IncidentDao,
    private val crypto: DomainCrypto,
) {
    suspend fun record(
        category: String,
        code: String,
        correlationId: String,
        safePayload: ByteArray,
        generation: Long? = null,
        coreProcessEpoch: String? = null,
        nowMillis: Long = System.currentTimeMillis(),
    ) {
        require(SAFE_CODE.matches(category) && SAFE_CODE.matches(code))
        require(correlationId.length in 1..128)
        require(safePayload.size <= MAX_SINGLE_INCIDENT_BYTES)
        val id = UUID.randomUUID().toString()
        val encrypted = crypto.encrypt(safePayload, "incident:$id".toByteArray(Charsets.UTF_8))
        dao.insert(
            IncidentEntity(
                id = id,
                occurredAtMillis = nowMillis,
                category = category,
                code = code,
                correlationId = correlationId,
                generation = generation,
                coreProcessEpoch = coreProcessEpoch,
                encryptedPayload = encrypted,
                sizeBytes = encrypted.size,
            ),
        )
        enforceRetention(nowMillis)
    }

    suspend fun exportDecrypted(): List<Pair<IncidentEntity, ByteArray>> =
        dao.recent(MAX_INCIDENT_COUNT).map { incident ->
            incident to crypto.decrypt(
                incident.encryptedPayload,
                "incident:${incident.id}".toByteArray(Charsets.UTF_8),
            )
        }

    private suspend fun enforceRetention(nowMillis: Long) {
        dao.deleteOlderThan(nowMillis - RETENTION_MILLIS)
        dao.trimCount(MAX_INCIDENT_COUNT)
        var total = dao.totalSizeBytes()
        if (total <= MAX_TOTAL_BYTES) return
        val oldestFirst = dao.recent(MAX_INCIDENT_COUNT).asReversed()
        val remove = mutableListOf<String>()
        for (incident in oldestFirst) {
            if (total <= MAX_TOTAL_BYTES) break
            remove += incident.id
            total -= incident.sizeBytes
        }
        if (remove.isNotEmpty()) dao.deleteIds(remove)
    }

    companion object {
        private val SAFE_CODE = Regex("^[a-z0-9._-]{1,96}$")
        private const val MAX_SINGLE_INCIDENT_BYTES = 64 * 1024
        private const val MAX_INCIDENT_COUNT = 1000
        private const val MAX_TOTAL_BYTES = 2L * 1024L * 1024L
        private const val RETENTION_MILLIS = 7L * 24L * 60L * 60L * 1000L
    }
}
