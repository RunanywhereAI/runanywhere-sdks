//
//  CppBridge+Strategy.swift
//  RunAnywhere SDK
//
//  Archive type C++ conversion extensions.
//  These are used by ModelTypes+CppBridge.swift for model artifact type handling.
//

import CRACommons
import Foundation

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
//
// TODO: add ArchiveStructure mapper in commons. T15a added proto<->C mappers
// for 5 enum pairs (InferenceFramework, ModelCategory, ModelFormat,
// ModelSource, ArchiveType) but not ArchiveStructure. Keep the hand-written
// switches here until commons exposes `rac_archive_structure_from/to_proto`.

extension ArchiveStructure {
    /// Convert to C++ archive structure
    func toC() -> rac_archive_structure_t {
        switch self {
        case .singleFileNested:     return RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED
        case .directoryBased:       return RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED
        case .nestedDirectory:      return RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY
        case .unknown:              return RAC_ARCHIVE_STRUCTURE_UNKNOWN
        default:                    return RAC_ARCHIVE_STRUCTURE_UNKNOWN
        }
    }

    /// Initialize from C++ archive structure
    init(from cStructure: rac_archive_structure_t) {
        switch cStructure {
        case RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED:   self = .singleFileNested
        case RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED:      self = .directoryBased
        case RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY:     self = .nestedDirectory
        default:                                         self = .unknown
        }
    }
}
