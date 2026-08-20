package io.hydrabox.client.core

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CoreBundleUpdaterTest {
    @Test
    fun `manifest accepts API major one and two but rejects three`() {
        assertEquals(1, CoreBundleManifest.parse(manifest(1)).coreApiMajor)
        assertEquals(2, CoreBundleManifest.parse(manifest(2)).coreApiMajor)
        assertThrows(IllegalArgumentException::class.java) {
            CoreBundleManifest.parse(manifest(3))
        }
    }

    @Test
    fun `selects newest release with signed bundle assets including prerelease`() {
        val releases = JSONArray(
            """
            [
              {
                "id": 9,
                "draft": false,
                "prerelease": false,
                "tag_name": "stable-without-bundle",
                "assets": [{"id": 90, "name": "libbox.aar", "size": 42}]
              },
              {
                "id": 14,
                "draft": false,
                "prerelease": true,
                "tag_name": "bundle-prerelease",
                "assets": [
                  {"id": 141, "name": "hydracore-bundle-manifest-v1.json", "size": 1024},
                  {"id": 142, "name": "hydracore-bundle-manifest-v1.sig", "size": 64}
                ]
              }
            ]
            """.trimIndent(),
        )

        val selected = selectCoreBundleRelease(
            releases,
            setOf(
                "hydracore-bundle-manifest-v1.json",
                "hydracore-bundle-manifest-v1.sig",
            ),
            CoreReleaseChannel.DEBUG,
        )

        assertEquals(14L, selected.getLong("id"))
        assertEquals("bundle-prerelease", selected.getString("tag_name"))
    }

    @Test
    fun `rejects draft and incomplete bundle releases`() {
        val releases = JSONArray(
            """
            [
              {
                "id": 15,
                "draft": true,
                "assets": [
                  {"id": 151, "name": "manifest", "size": 10},
                  {"id": 152, "name": "signature", "size": 64}
                ]
              },
              {
                "id": 14,
                "draft": false,
                "assets": [{"id": 141, "name": "manifest", "size": 10}]
              }
            ]
            """.trimIndent(),
        )

        assertThrows(IllegalStateException::class.java) {
            selectCoreBundleRelease(
                releases,
                setOf("manifest", "signature"),
                CoreReleaseChannel.DEBUG,
            )
        }
    }

    @Test
    fun `stable channel ignores newer debug bundle`() {
        val releases = JSONArray(
            """
            [
              {
                "id": 20,
                "draft": false,
                "prerelease": true,
                "assets": [
                  {"id": 201, "name": "manifest", "size": 10},
                  {"id": 202, "name": "signature", "size": 64}
                ]
              },
              {
                "id": 19,
                "draft": false,
                "prerelease": false,
                "assets": [
                  {"id": 191, "name": "manifest", "size": 10},
                  {"id": 192, "name": "signature", "size": 64}
                ]
              }
            ]
            """.trimIndent(),
        )

        val selected = selectCoreBundleRelease(
            releases,
            setOf("manifest", "signature"),
            CoreReleaseChannel.STABLE,
        )

        assertEquals(19L, selected.getLong("id"))
    }

    private fun manifest(apiMajor: Int): ByteArray =
        """
        {
          "schemaVersion": 1,
          "distributionId": "io.hydrabox.hydracore",
          "releaseSequence": 1,
          "version": "test",
          "sourceCommit": "0000000000000000000000000000000000000000",
          "upstreamCommit": "0000000000000000000000000000000000000000",
          "publishedAt": "2026-08-20T00:00:00Z",
          "coreApiMajor": $apiMajor,
          "coreApiMinor": 0,
          "runtimeSnapshotSchema": {"min": 1, "max": 1},
          "runtimeEventSchema": {"min": 1, "max": 1},
          "configSchema": {"min": 1, "max": 1},
          "subscriptionSchema": {"min": 2, "max": 2},
          "capabilitiesSha256": "0000000000000000000000000000000000000000000000000000000000000000",
          "keyId": "test",
          "artifacts": [{
            "abi": "arm64-v8a",
            "assetName": "libbox.so",
            "sizeBytes": 1,
            "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
            "minSdk": 26
          }]
        }
        """.trimIndent().toByteArray()
}
