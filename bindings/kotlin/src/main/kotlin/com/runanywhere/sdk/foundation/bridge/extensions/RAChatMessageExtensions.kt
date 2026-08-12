/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * RAChatMessageExtensions.kt
 *
 * Extensions for proto-generated chat types.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/RAChatMessage+Extensions.swift`.
 *
 * Swift exposes `RAMessageRole.wireString` plus a `Codable` conformance that
 * round-trips lowercase wire strings ("user", "assistant", …). Kotlin
 * doesn't use Codable, but the same lowercase wire convention is shared
 * across Kotlin/Dart/RN/Web JSON payloads — this file provides the
 * accessors needed to participate in that contract.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.MessageRole

// MARK: - MessageRole convenience

/**
 * Canonical lowercase wire string for a chat role ("user", "assistant",
 * "system", "tool"). Mirrors Swift `RAMessageRole.wireString`. Falls back
 * to "unspecified" for the proto default + unknown / developer roles to
 * keep parity with the Swift sentinel.
 */
val MessageRole.wireString: String
    get() =
        when (this) {
            MessageRole.MESSAGE_ROLE_USER -> "user"
            MessageRole.MESSAGE_ROLE_ASSISTANT -> "assistant"
            MessageRole.MESSAGE_ROLE_SYSTEM -> "system"
            MessageRole.MESSAGE_ROLE_TOOL -> "tool"
            MessageRole.MESSAGE_ROLE_DEVELOPER -> "developer"
            MessageRole.MESSAGE_ROLE_UNSPECIFIED -> "unspecified"
        }

/**
 * Parse a wire-format chat role string ("user", "assistant", …) into the
 * canonical proto enum. Case-insensitive. Returns `null` on unknown inputs
 * so JSON decoders can choose how to fall back (Swift falls back to
 * `.unspecified`; consumer code can do `?: MESSAGE_ROLE_UNSPECIFIED`).
 *
 * Mirrors Swift `RAMessageRole.init?(wireString:)`.
 */
fun messageRoleFromWireString(value: String): MessageRole? =
    when (value.lowercase()) {
        "user" -> MessageRole.MESSAGE_ROLE_USER
        "assistant" -> MessageRole.MESSAGE_ROLE_ASSISTANT
        "system" -> MessageRole.MESSAGE_ROLE_SYSTEM
        "tool" -> MessageRole.MESSAGE_ROLE_TOOL
        "developer" -> MessageRole.MESSAGE_ROLE_DEVELOPER
        else -> null
    }
