// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

@_exported import RunAnywhere

public enum ONNXRuntimeBackend {
    public static func ensureRegistered(priority: Int = 100) -> Bool {
        ONNX.register(priority: priority)
    }
}
