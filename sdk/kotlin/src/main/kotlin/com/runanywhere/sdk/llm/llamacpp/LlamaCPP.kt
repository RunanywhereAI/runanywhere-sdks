// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Re-export the canonical LlamaCPP register object under the legacy
// package path `com.runanywhere.sdk.llm.llamacpp` so sample apps that
// import `com.runanywhere.sdk.llm.llamacpp.LlamaCPP` still resolve.

package com.runanywhere.sdk.llm.llamacpp

typealias LlamaCPP = com.runanywhere.sdk.`public`.LlamaCPP
