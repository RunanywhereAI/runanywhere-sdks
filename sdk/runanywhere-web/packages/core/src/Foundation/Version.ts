/**
 * SDK Version Constant.
 *
 * This file is the canonical source for the Web SDK public version string.
 * It is kept in sync with `sdk/runanywhere-commons/VERSION` by
 * `scripts/release/sync-versions.sh`, which rewrites the `SDK_VERSION` export below
 * alongside `SDKConstants.swift`, Kotlin `gradle.properties`, and the
 * per-package `package.json` versions.
 *
 * Do not hand-edit — update `sdk/runanywhere-commons/VERSION` and run
 * `scripts/release/sync-versions.sh <new_version>`.
 */
export const SDK_VERSION = '0.19.13';
