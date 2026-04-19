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
    /// Convert to C++ archive type
    func toC() -> rac_archive_type_t {
        switch self {
        case .zip:
            return RAC_ARCHIVE_TYPE_ZIP
        case .tarBz2:
            return RAC_ARCHIVE_TYPE_TAR_BZ2
        case .tarGz:
            return RAC_ARCHIVE_TYPE_TAR_GZ
        case .tarXz:
            return RAC_ARCHIVE_TYPE_TAR_XZ
        }
    }

    /// Initialize from C++ archive type
    init?(from cType: rac_archive_type_t) {
        switch cType {
        case RAC_ARCHIVE_TYPE_ZIP:
            self = .zip
        case RAC_ARCHIVE_TYPE_TAR_BZ2:
            self = .tarBz2
        case RAC_ARCHIVE_TYPE_TAR_GZ:
            self = .tarGz
        case RAC_ARCHIVE_TYPE_TAR_XZ:
            self = .tarXz
        default:
            return nil
        }
    }
}

// MARK: - ArchiveStructure C++ Conversion

extension ArchiveStructure {
    /// Convert to C++ archive structure
    func toC() -> rac_archive_structure_t {
        switch self {
        case .singleFileNested:
            return RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED
        case .directoryBased:
            return RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED
        case .nestedDirectory:
            return RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY
        case .unknown:
            return RAC_ARCHIVE_STRUCTURE_UNKNOWN
        }
    }

    /// Initialize from C++ archive structure
    init(from cStructure: rac_archive_structure_t) {
        switch cStructure {
        case RAC_ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED:
            self = .singleFileNested
        case RAC_ARCHIVE_STRUCTURE_DIRECTORY_BASED:
            self = .directoryBased
        case RAC_ARCHIVE_STRUCTURE_NESTED_DIRECTORY:
            self = .nestedDirectory
        default:
            self = .unknown
        }
    }
}
