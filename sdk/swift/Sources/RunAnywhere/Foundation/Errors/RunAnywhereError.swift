// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation
import CRACommonsCore

/// Canonical error type produced by every `ra_*` bridge. Maps raw
/// `ra_status_t` codes onto semantic Swift cases so call sites can pattern
/// match without leaking C ABI values.
public enum RunAnywhereError: Error, CustomStringConvertible, Sendable {
    case backendUnavailable(String)
    case modelNotFound(String)
    case cancelled
    case abiMismatch(expected: UInt32, got: UInt32)
    case internalError(String)
    case invalidArgument(String)
    case outOfMemory(String)
    case ioError(String)
    case timeout(String)
    case capabilityUnsupported(String)

    public var description: String {
        switch self {
        case .backendUnavailable(let m): return "backend unavailable: \(m)"
        case .modelNotFound(let m):      return "model not found: \(m)"
        case .cancelled:                 return "cancelled"
        case .abiMismatch(let e, let g): return "ABI mismatch: expected \(e), got \(g)"
        case .internalError(let m):      return "internal: \(m)"
        case .invalidArgument(let m):    return "invalid argument: \(m)"
        case .outOfMemory(let m):        return "out of memory: \(m)"
        case .ioError(let m):            return "io error: \(m)"
        case .timeout(let m):            return "timeout: \(m)"
        case .capabilityUnsupported(let m): return "capability unsupported: \(m)"
        }
    }

    /// Convenience initialiser that maps a raw `ra_status_t` status into the
    /// matching enum case. `context` is included in the message.
    public init(status: Int32, context: String) {
        switch status {
        case Int32(RA_ERR_CANCELLED):              self = .cancelled
        case Int32(RA_ERR_INVALID_ARGUMENT):       self = .invalidArgument(context)
        case Int32(RA_ERR_MODEL_LOAD_FAILED):      self = .modelNotFound(context)
        case Int32(RA_ERR_MODEL_NOT_FOUND):        self = .modelNotFound(context)
        case Int32(RA_ERR_RUNTIME_UNAVAILABLE),
             Int32(RA_ERR_BACKEND_UNAVAILABLE):    self = .backendUnavailable(context)
        case Int32(RA_ERR_CAPABILITY_UNSUPPORTED): self = .capabilityUnsupported(context)
        case Int32(RA_ERR_OUT_OF_MEMORY):          self = .outOfMemory(context)
        case Int32(RA_ERR_IO):                     self = .ioError(context)
        case Int32(RA_ERR_TIMEOUT):                self = .timeout(context)
        default:                                    self = .internalError("\(context) (status=\(status))")
        }
    }
}
