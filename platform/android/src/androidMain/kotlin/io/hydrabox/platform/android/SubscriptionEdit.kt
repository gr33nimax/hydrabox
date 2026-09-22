package io.hydrabox.platform.android

/**
 * What editing a stored subscription amounts to, decided before anything is fetched or written.
 *
 * An address is a source's identity: [io.hydrabox.core.subscription.SubscriptionId.of] hashes it,
 * so a new address means a new storage id, a new document and new metadata — while the name and
 * the switch are the person's, not the address's. Keeping the decision here, away from the
 * database, is what makes "an edit that cannot be completed changes nothing" checkable.
 */
internal enum class SubscriptionEdit {
    /** Only the name changes: the address stays, so nothing is fetched. */
    RENAME,

    /** The address moves to one no other stored source uses: it is fetched, then replaced. */
    MOVE,

    /** The typed address belongs to another stored source: the edit is refused. */
    TAKEN,
}

internal fun subscriptionEdit(
    storedUrl: String?,
    typedUrl: String,
    ownerOfTypedUrl: String?,
    id: String,
): SubscriptionEdit =
    when {
        // An empty field is not an instruction to forget the address: the sheet is prefilled
        // with it, and a person clearing it means "leave it as it is".
        typedUrl.isBlank() || typedUrl == storedUrl -> SubscriptionEdit.RENAME

        // Two stored sources on one address would be one source that can be refreshed twice
        // and deleted once, so the second one is refused rather than created.
        ownerOfTypedUrl != null && ownerOfTypedUrl != id -> SubscriptionEdit.TAKEN

        else -> SubscriptionEdit.MOVE
    }
