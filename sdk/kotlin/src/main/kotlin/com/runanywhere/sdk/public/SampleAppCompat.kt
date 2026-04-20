// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Sample-app compat overlay — the Android sample references these symbols
// verbatim. Kept in a separate file from the public API so it can evolve
// without polluting the canonical surface.

package com.runanywhere.sdk.`public`

// Backend register objects + initialize / isInitialized /
// completeServicesInitialization are declared on the RunAnywhere object
// directly (see RunAnywhere.kt and Sessions.kt). This file remains for
// future sample-app-only shims that don't belong on the canonical object.
