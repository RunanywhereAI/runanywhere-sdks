//
//  CppBridge+Strategy.swift
//  RunAnywhere SDK
//
//  Archive type C++ conversion extensions.
//  These are used by ModelTypes+CppBridge.swift for model artifact type handling.
//

import CRACommons

// MARK: - ArchiveType C++ Conversion

extension ArchiveType {
    /// Convert to C++ archive type.
    /// Delegates to commons' `rac_archive_type_from_proto`. Falls back to
    /// `RAC_ARCHIVE_TYPE_ZIP` when the proto value is unrecognized (preserves
    /// legacy hand-written behaviour for unspecified inputs).
    func toC() -> rac_archive_type_t {
        var out: rac_archive_type_t = RAC_ARCHIVE_TYPE_ZIP
        guard rac_archive_type_from_proto(Int32(self.rawValue), &out) == RAC_SUCCESS else {
            return RAC_ARCHIVE_TYPE_ZIP
        }
        return out
    }

    /// Initialize from C++ archive type.
    /// Delegates to commons' `rac_archive_type_to_proto`. Returns nil for
    /// unrecognized C values (matches legacy hand-written switch).
    init?(from cType: rac_archive_type_t) {
        var protoValue: Int32 = 0
        guard rac_archive_type_to_proto(cType, &protoValue) == RAC_SUCCESS,
              let resolved = ArchiveType(rawValue: Int(protoValue)) else {
            return nil
        }
        self = resolved
    }
}

// MARK: - ArchiveStructure C++ Conversion

extension ArchiveStructure {
    /// Initialize from C++ archive structure.
    /// Delegates to commons' `rac_archive_structure_to_proto`. Falls back to
    /// `.unknown` for unrecognized C values (matches legacy hand-written switch).
    init(from cStructure: rac_archive_structure_t) {
        var protoValue: Int32 = 0
        guard rac_archive_structure_to_proto(cStructure, &protoValue) == RAC_SUCCESS,
              let resolved = ArchiveStructure(rawValue: Int(protoValue)) else {
            self = .unknown
            return
        }
        self = resolved
    }
}
