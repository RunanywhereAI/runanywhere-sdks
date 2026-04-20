// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Static-plugin registration DSL for iOS (where dlopen is prohibited).

import Foundation

public struct RegistrationBuilder {
    public internal(set) var registeredEngines: [String] = []

    /// Register a static plugin by its metadata name. On iOS this call maps
    /// to the `RA_STATIC_PLUGIN_REGISTER` macro in the C core; on
    /// macOS/Linux it's a hint used if no dlopen path works.
    public mutating func register(_ name: String) {
        registeredEngines.append(name)
    }

    internal func apply() {
        // TODO(phase-1): call into ra_registry_register_static for each
        // name via a dyld-time resolution hook provided by the XCFramework.
    }
}
