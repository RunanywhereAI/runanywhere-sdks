// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Thin Swift adapter over the `ra_telemetry_*` C ABI. Provides typed
// `RunAnywhere.telemetry.*` call sites backed by the core telemetry
// module. Platforms inject their HTTP transport once via
// `PlatformAdapter`, then these helpers emit events uniformly.

import Foundation
import CRACommonsCore

public struct DeviceRegistrationInfo: Sendable {
    public var deviceId: String
    public var osName: String
    public var osVersion: String
    public var appVersion: String
    public var sdkVersion: String
    public var modelName: String
    public var chipName: String
    public var totalMemoryBytes: Int64
    public var availableStorageBytes: Int64

    public init(deviceId: String, osName: String, osVersion: String,
                appVersion: String, sdkVersion: String,
                modelName: String, chipName: String,
                totalMemoryBytes: Int64, availableStorageBytes: Int64) {
        self.deviceId = deviceId
        self.osName = osName
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.sdkVersion = sdkVersion
        self.modelName = modelName
        self.chipName = chipName
        self.totalMemoryBytes = totalMemoryBytes
        self.availableStorageBytes = availableStorageBytes
    }
}

@MainActor
public enum Telemetry {

    /// Track a named event with optional JSON-stringified properties.
    @discardableResult
    public static func track(event: String, propertiesJson: String = "{}") -> Bool {
        event.withCString { n in
            propertiesJson.withCString { p in
                ra_telemetry_track(n, p) == RA_OK
            }
        }
    }

    /// Force-flush any buffered telemetry events to the registered uploader.
    @discardableResult
    public static func flush() -> Bool {
        ra_telemetry_flush() == RA_OK
    }

    /// Returns the default platform-agnostic telemetry payload (SDK
    /// version + platform), suitable for merging with event-specific
    /// properties before upload.
    public static func defaultPayloadJson() -> String {
        var out: UnsafeMutablePointer<CChar>?
        guard ra_telemetry_payload_default(&out) == RA_OK, let raw = out else {
            return "{}"
        }
        defer { ra_telemetry_string_free(out) }
        return String(cString: raw)
    }

    /// Serialise a `DeviceRegistrationInfo` to JSON using the core
    /// canonical shape. The returned string is ready to POST to
    /// `ra_device_registration_endpoint()`.
    public static func deviceRegistrationJson(
        _ info: DeviceRegistrationInfo) -> String {
        info.deviceId.withCString { id in
            info.osName.withCString { os in
                info.osVersion.withCString { osv in
                    info.appVersion.withCString { app in
                        info.sdkVersion.withCString { sdk in
                            info.modelName.withCString { model in
                                info.chipName.withCString { chip in
                                    var raInfo = ra_device_registration_info_t()
                                    raInfo.device_id               = id
                                    raInfo.os_name                 = os
                                    raInfo.os_version              = osv
                                    raInfo.app_version             = app
                                    raInfo.sdk_version             = sdk
                                    raInfo.model_name              = model
                                    raInfo.chip_name               = chip
                                    raInfo.total_memory_bytes      = info.totalMemoryBytes
                                    raInfo.available_storage_bytes = info.availableStorageBytes
                                    var out: UnsafeMutablePointer<CChar>?
                                    guard withUnsafePointer(to: raInfo, {
                                        ra_device_registration_to_json($0, &out)
                                    }) == RA_OK, let raw = out else {
                                        return "{}"
                                    }
                                    defer { ra_telemetry_string_free(out) }
                                    return String(cString: raw)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Returns the canonical device-registration endpoint URL
    /// (derived from the current environment).
    public static func deviceRegistrationEndpoint() -> String {
        guard let ptr = ra_device_registration_endpoint() else { return "" }
        return String(cString: ptr)
    }
}

@MainActor
public extension RunAnywhere {
    /// Namespaced telemetry entry point. Sample apps call
    /// `RunAnywhere.telemetry.track(event: "model_loaded")`.
    static var telemetry: Telemetry.Type { Telemetry.self }
}
