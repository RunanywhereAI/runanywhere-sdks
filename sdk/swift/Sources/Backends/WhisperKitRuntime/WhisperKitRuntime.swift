// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

@_exported import RunAnywhere

public enum WhisperKitRuntimeBackend {
    public static func ensureRegistered(priority: Int = 200) -> Bool {
        WhisperKitSTT.register(priority: priority)
    }
}
