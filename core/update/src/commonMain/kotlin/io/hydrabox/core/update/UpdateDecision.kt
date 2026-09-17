package io.hydrabox.core.update

/** What the client decided about a release document it fetched. */
sealed interface UpdateDecision {
    /** Nothing to do: either nothing newer exists, or the document was not for us. */
    data object NoUpdate : UpdateDecision

    /** A verified, newer release for the selected channel. */
    data class Available(
        val manifest: UpdateManifest,
    ) : UpdateDecision

    /** The document cannot be used, and this is why. */
    data class Refused(
        val fault: UpdateFault,
    ) : UpdateDecision
}

/**
 * Why a fetched document did not lead to an update. One vocabulary for the caller, so a screen
 * never has to know which layer refused.
 */
enum class UpdateFault {
    /** The core did not vouch for these bytes. Nothing else is even examined. */
    UNVERIFIED,

    MALFORMED,
    UNSUPPORTED_SCHEMA,
    EMPTY_FIELD,
    INSECURE_URL,
    BAD_DIGEST,

    /** A release for a line this person did not choose. */
    WRONG_CHANNEL,
}

/**
 * Why staging an install did not reach Android's confirmation. Separate from [UpdateFault]
 * because a document can be perfectly sound and the artifact still unusable.
 */
enum class InstallFault {
    /** The artifact could not be read. */
    UNREACHABLE,

    /** Larger than this client will hold, declared or counted. */
    TOO_LARGE,

    /** The bytes do not hash to what the manifest promised. */
    DIGEST_MISMATCH,

    /** Signed by a key this application does not install from. */
    CERTIFICATE_MISMATCH,

    /** Android's installer refused to open a session, or this build may not ask it to. */
    NO_INSTALLER,
}

/**
 * Decides what to do with a fetched release document.
 *
 * The order is the point, and it is the reason this is one function rather than a few checks
 * spread across a screen: a document nobody vouched for is never parsed into a decision, a
 * document for another release line is never compared with what is installed, and only a
 * verified, on-channel, strictly newer release becomes something a person can install.
 *
 * [signatureVerified] is not a hint. It is the core's verdict on the exact bytes in
 * [manifestBody], and passing true without that verdict turns this whole function into a
 * formality.
 */
fun decideUpdate(
    manifestBody: String,
    signatureVerified: Boolean,
    selectedChannel: String,
    installedVersionCode: Int,
): UpdateDecision {
    if (!signatureVerified) return UpdateDecision.Refused(UpdateFault.UNVERIFIED)
    if (manifestBody.isBlank()) return UpdateDecision.Refused(UpdateFault.MALFORMED)
    val manifest =
        when (val outcome = UpdateManifestParser.parse(manifestBody)) {
            is ManifestOutcome.Rejected -> return UpdateDecision.Refused(outcome.fault.toUpdateFault())
            is ManifestOutcome.Accepted -> outcome.manifest
        }
    if (!manifest.matchesChannel(selectedChannel)) return UpdateDecision.Refused(UpdateFault.WRONG_CHANNEL)
    // A document that is not newer is not a failure worth showing: switching release lines
    // legitimately points at an older build, and an equal version code is a reinstall Android
    // would refuse anyway.
    return if (manifest.isNewerThan(installedVersionCode)) UpdateDecision.Available(manifest) else UpdateDecision.NoUpdate
}

private fun ManifestFault.toUpdateFault(): UpdateFault =
    when (this) {
        ManifestFault.MALFORMED -> UpdateFault.MALFORMED
        ManifestFault.UNSUPPORTED_SCHEMA -> UpdateFault.UNSUPPORTED_SCHEMA
        ManifestFault.EMPTY_FIELD -> UpdateFault.EMPTY_FIELD
        ManifestFault.INSECURE_URL -> UpdateFault.INSECURE_URL
        ManifestFault.BAD_DIGEST -> UpdateFault.BAD_DIGEST
    }
