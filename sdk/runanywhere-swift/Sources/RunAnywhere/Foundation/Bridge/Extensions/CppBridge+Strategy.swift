//
//  CppBridge+Strategy.swift
//  RunAnywhere SDK
//
//  Model storage and download strategy bridge.
//  Strategies are registered by backends in C++ and accessed via this bridge.
//

import CRACommons
import Foundation

// MARK: - Model Storage Details

/// Swift wrapper for C++ model storage details
public struct ModelStorageDetails: Sendable {
    /// Model format detected
    public let format: ModelFormat

    /// Total size on disk in bytes
    public let totalSize: Int64

    /// Number of files in the model directory
    public let fileCount: Int

    /// Primary model file name (e.g., "model.onnx")
    public let primaryFile: String?

    /// Whether this is a directory-based model (vs single file)
    public let isDirectoryBased: Bool

    /// Whether the model storage is valid/complete
    public let isValid: Bool

    public init(
        format: ModelFormat,
        totalSize: Int64,
        fileCount: Int,
        primaryFile: String? = nil,
        isDirectoryBased: Bool = false,
        isValid: Bool = true
    ) {
        self.format = format
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.primaryFile = primaryFile
        self.isDirectoryBased = isDirectoryBased
        self.isValid = isValid
    }

    /// Initialize from C++ storage details
    init(from cDetails: rac_model_storage_details_t) {
        self.format = ModelFormat(from: cDetails.format)
        self.totalSize = cDetails.total_size
        self.fileCount = Int(cDetails.file_count)
        self.primaryFile = cDetails.primary_file.map { String(cString: $0) }
        self.isDirectoryBased = cDetails.is_directory_based == RAC_TRUE
        self.isValid = cDetails.is_valid == RAC_TRUE
    }
}

// MARK: - Model Download Strategy Config

/// Configuration for model download strategy (different from DownloadConfiguration)
/// This is used by the C++ strategy layer for backend-specific download handling.
public struct ModelDownloadStrategyConfig: Sendable {
    /// Model ID being downloaded
    public let modelId: String

    /// Source URL for download
    public let sourceURL: URL

    /// Destination folder path
    public let destinationFolder: URL

    /// Expected archive type (nil for direct files)
    public let archiveType: ArchiveType?

    /// Expected total size in bytes (0 if unknown)
    public let expectedSize: Int64

    /// Whether to resume partial downloads
    public let allowResume: Bool

    public init(
        modelId: String,
        sourceURL: URL,
        destinationFolder: URL,
        archiveType: ArchiveType? = nil,
        expectedSize: Int64 = 0,
        allowResume: Bool = true
    ) {
        self.modelId = modelId
        self.sourceURL = sourceURL
        self.destinationFolder = destinationFolder
        self.archiveType = archiveType
        self.expectedSize = expectedSize
        self.allowResume = allowResume
    }

    /// Convert to C++ download config
    func toC() -> rac_model_download_config_t {
        var config = rac_model_download_config_t()
        // Note: Strings need to be kept alive by caller
        return config
    }
}

// MARK: - Download Result

/// Result of a download operation
public struct DownloadResult: Sendable {
    /// Final path to the downloaded/extracted model
    public let finalPath: URL

    /// Actual size downloaded in bytes
    public let downloadedSize: Int64

    /// Whether extraction was performed
    public let wasExtracted: Bool

    /// Number of files after extraction (1 for single file)
    public let fileCount: Int

    public init(
        finalPath: URL,
        downloadedSize: Int64,
        wasExtracted: Bool,
        fileCount: Int
    ) {
        self.finalPath = finalPath
        self.downloadedSize = downloadedSize
        self.wasExtracted = wasExtracted
        self.fileCount = fileCount
    }

    /// Initialize from C++ download result
    init?(from cResult: rac_download_result_t) {
        guard let pathPtr = cResult.final_path else { return nil }
        self.finalPath = URL(fileURLWithPath: String(cString: pathPtr))
        self.downloadedSize = cResult.downloaded_size
        self.wasExtracted = cResult.was_extracted == RAC_TRUE
        self.fileCount = Int(cResult.file_count)
    }
}

// MARK: - Strategy Bridge

extension CppBridge {

    /// Model strategy bridge
    /// Provides access to backend-registered storage and download strategies
    public enum Strategy {

        private static let logger = SDKLogger(category: "CppBridge.Strategy")
        private static let pathBufferSize = 1024

        // MARK: - Storage Strategy API

        /// Find model path using framework's storage strategy
        ///
        /// Each backend registers how to locate models within their storage structure.
        /// For example, ONNX models may be nested in subdirectories.
        ///
        /// - Parameters:
        ///   - framework: Inference framework
        ///   - modelId: Model identifier
        ///   - modelFolder: Model folder URL
        /// - Returns: Resolved model path, or nil if not found
        public static func findModelPath(
            framework: InferenceFramework,
            modelId: String,
            modelFolder: URL
        ) -> URL? {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)

            let result = modelId.withCString { mid in
                modelFolder.path.withCString { folder in
                    rac_model_strategy_find_path(
                        framework.toCFramework(),
                        mid,
                        folder,
                        &buffer,
                        buffer.count
                    )
                }
            }

            guard result == RAC_SUCCESS else {
                logger.debug("No model path found for \(modelId) in \(modelFolder.path)")
                return nil
            }

            return URL(fileURLWithPath: String(cString: buffer))
        }

        /// Detect model using framework's storage strategy
        ///
        /// - Parameters:
        ///   - framework: Inference framework
        ///   - modelFolder: Model folder URL
        /// - Returns: Storage details if model detected
        public static func detectModel(
            framework: InferenceFramework,
            modelFolder: URL
        ) -> ModelStorageDetails? {
            var cDetails = rac_model_storage_details_t()

            let result = modelFolder.path.withCString { folder in
                rac_model_strategy_detect(
                    framework.toCFramework(),
                    folder,
                    &cDetails
                )
            }

            guard result == RAC_SUCCESS else {
                return nil
            }

            defer { rac_model_storage_details_free(&cDetails) }
            return ModelStorageDetails(from: cDetails)
        }

        /// Validate model storage using framework's strategy
        ///
        /// - Parameters:
        ///   - framework: Inference framework
        ///   - modelFolder: Model folder URL
        /// - Returns: True if storage is valid
        public static func isValidStorage(
            framework: InferenceFramework,
            modelFolder: URL
        ) -> Bool {
            let result = modelFolder.path.withCString { folder in
                rac_model_strategy_is_valid(framework.toCFramework(), folder)
            }
            return result == RAC_TRUE
        }

        // MARK: - Download Strategy API

        /// Get download destination using framework's strategy
        ///
        /// - Parameters:
        ///   - framework: Inference framework
        ///   - modelId: Model identifier
        ///   - sourceURL: Source download URL
        ///   - baseFolder: Base folder for models
        /// - Returns: Destination path for download
        public static func getDownloadDestination(
            framework: InferenceFramework,
            modelId: String,
            sourceURL: URL,
            baseFolder: URL
        ) -> URL? {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)

            var config = rac_model_download_config_t()

            let result = modelId.withCString { mid in
                sourceURL.absoluteString.withCString { url in
                    baseFolder.path.withCString { folder in
                        config.model_id = mid
                        config.source_url = url
                        config.destination_folder = folder
                        config.archive_type = RAC_ARCHIVE_TYPE_NONE
                        config.expected_size = 0
                        config.allow_resume = RAC_TRUE

                        return rac_model_strategy_get_download_dest(
                            framework.toCFramework(),
                            &config,
                            &buffer,
                            buffer.count
                        )
                    }
                }
            }

            guard result == RAC_SUCCESS else {
                return nil
            }

            return URL(fileURLWithPath: String(cString: buffer))
        }

        /// Prepare download using framework's strategy
        ///
        /// - Parameters:
        ///   - framework: Inference framework
        ///   - config: Download configuration
        /// - Returns: True if preparation succeeded
        public static func prepareDownload(
            framework: InferenceFramework,
            modelId: String,
            sourceURL: URL,
            destinationFolder: URL,
            archiveType: ArchiveType? = nil
        ) -> Bool {
            var config = rac_model_download_config_t()

            let result = modelId.withCString { mid in
                sourceURL.absoluteString.withCString { url in
                    destinationFolder.path.withCString { folder in
                        config.model_id = mid
                        config.source_url = url
                        config.destination_folder = folder
                        config.archive_type = archiveType?.toC() ?? RAC_ARCHIVE_TYPE_NONE
                        config.allow_resume = RAC_TRUE

                        return rac_model_strategy_prepare_download(
                            framework.toCFramework(),
                            &config
                        )
                    }
                }
            }

            return result == RAC_SUCCESS
        }

        /// Post-process download using framework's strategy
        ///
        /// - Parameters:
        ///   - framework: Inference framework
        ///   - modelId: Model identifier
        ///   - downloadedPath: Path to downloaded file
        ///   - destinationFolder: Destination folder
        /// - Returns: Download result with final path
        public static func postProcessDownload(
            framework: InferenceFramework,
            modelId: String,
            downloadedPath: URL,
            destinationFolder: URL,
            archiveType: ArchiveType? = nil
        ) -> DownloadResult? {
            var config = rac_model_download_config_t()
            var cResult = rac_download_result_t()

            let result = modelId.withCString { mid in
                downloadedPath.path.withCString { dlPath in
                    destinationFolder.path.withCString { folder in
                        config.model_id = mid
                        config.destination_folder = folder
                        config.archive_type = archiveType?.toC() ?? RAC_ARCHIVE_TYPE_NONE

                        return rac_model_strategy_post_process(
                            framework.toCFramework(),
                            &config,
                            dlPath,
                            &cResult
                        )
                    }
                }
            }

            guard result == RAC_SUCCESS else {
                return nil
            }

            defer { rac_download_result_free(&cResult) }
            return DownloadResult(from: cResult)
        }

        // MARK: - Strategy Registration Check

        /// Check if a storage strategy is registered for a framework
        public static func hasStorageStrategy(for framework: InferenceFramework) -> Bool {
            return rac_storage_strategy_get(framework.toCFramework()) != nil
        }

        /// Check if a download strategy is registered for a framework
        public static func hasDownloadStrategy(for framework: InferenceFramework) -> Bool {
            return rac_download_strategy_get(framework.toCFramework()) != nil
        }
    }
}

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
