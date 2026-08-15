package io.hydrabox.client.core

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CoreBundleUpdaterTest {
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
            selectCoreBundleRelease(releases, setOf("manifest", "signature"))
        }
    }
}
