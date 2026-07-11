package com.runanywhere.runanywhereai.data.security

/** Failure stages are deliberately content-free so migration diagnostics never expose secrets. */
internal enum class PreferenceMigrationFailure {
    SECURE_READ,
    SECURE_VALUE_INVALID,
    LEGACY_READ,
    LEGACY_VALUE_INVALID,
    SECURE_WRITE,
    SECURE_VERIFY,
    LEGACY_REMOVE,
}

internal data class StringPreferenceMigrationResult(
    val value: String?,
    val migrated: Boolean = false,
    val failure: PreferenceMigrationFailure? = null,
)

/**
 * Atomically moves one sensitive string into encrypted storage.
 *
 * The legacy value is removed only after the secure write commits and a fresh read verifies the
 * exact normalized value. Re-running the migration is safe: an existing valid secure value is
 * authoritative and only triggers cleanup of a leftover legacy copy. Callers that persist an
 * explicit blank tombstone can opt into treating that value as authoritative too.
 */
internal fun migrateSensitiveString(
    readSecure: () -> String?,
    readLegacy: () -> String?,
    writeSecure: (String) -> Boolean,
    removeLegacy: () -> Boolean,
    normalize: (String) -> String = { it },
    validate: (String) -> Boolean = { true },
    allowBlankSecureValue: Boolean = false,
): StringPreferenceMigrationResult {
    val secureValue = runCatching(readSecure).getOrElse {
        return StringPreferenceMigrationResult(null, failure = PreferenceMigrationFailure.SECURE_READ)
    }
    if (secureValue != null && (secureValue.isNotBlank() || allowBlankSecureValue)) {
        val normalizedSecure = runCatching { normalize(secureValue) }.getOrNull()
        if (normalizedSecure == null || !runCatching { validate(normalizedSecure) }.getOrDefault(false)) {
            return StringPreferenceMigrationResult(
                null,
                failure = PreferenceMigrationFailure.SECURE_VALUE_INVALID,
            )
        }
        val legacyValue = runCatching(readLegacy).getOrElse {
            return StringPreferenceMigrationResult(
                normalizedSecure,
                failure = PreferenceMigrationFailure.LEGACY_READ,
            )
        }
        if (legacyValue != null && !runCatching(removeLegacy).getOrDefault(false)) {
            return StringPreferenceMigrationResult(
                normalizedSecure,
                failure = PreferenceMigrationFailure.LEGACY_REMOVE,
            )
        }
        return StringPreferenceMigrationResult(normalizedSecure)
    }

    val legacyValue = runCatching(readLegacy).getOrElse {
        return StringPreferenceMigrationResult(null, failure = PreferenceMigrationFailure.LEGACY_READ)
    }
    if (legacyValue.isNullOrBlank()) return StringPreferenceMigrationResult(null)

    val normalizedLegacy = runCatching { normalize(legacyValue) }.getOrNull()
    if (normalizedLegacy == null ||
        normalizedLegacy.isBlank() ||
        !runCatching { validate(normalizedLegacy) }.getOrDefault(false)
    ) {
        return StringPreferenceMigrationResult(
            null,
            failure = PreferenceMigrationFailure.LEGACY_VALUE_INVALID,
        )
    }
    if (!runCatching { writeSecure(normalizedLegacy) }.getOrDefault(false)) {
        return StringPreferenceMigrationResult(null, failure = PreferenceMigrationFailure.SECURE_WRITE)
    }
    val verified = runCatching(readSecure).getOrElse {
        return StringPreferenceMigrationResult(null, failure = PreferenceMigrationFailure.SECURE_VERIFY)
    }
    if (verified != normalizedLegacy) {
        return StringPreferenceMigrationResult(null, failure = PreferenceMigrationFailure.SECURE_VERIFY)
    }
    if (!runCatching(removeLegacy).getOrDefault(false)) {
        return StringPreferenceMigrationResult(
            normalizedLegacy,
            migrated = true,
            failure = PreferenceMigrationFailure.LEGACY_REMOVE,
        )
    }
    return StringPreferenceMigrationResult(normalizedLegacy, migrated = true)
}
