//
//  CppBridge+ModelPaths.swift
//  RunAnywhere SDK
//
//  Model path utilities bridge extension for C++ interop.
//

import CRACommons
import Foundation

// MARK: - ModelPaths Bridge

extension CppBridge {

    /// Model path utilities bridge
    /// Wraps C++ rac_model_paths.h functions
    public enum ModelPaths {

        private static let logger = SDKLogger(category: "CppBridge.ModelPaths")
        private static let pathBufferSize = 1024

        // MARK: - Configuration

        /// Set the base directory for model storage
        /// Must be called during SDK initialization
        public static func setBaseDirectory(_ baseDir: URL) throws {
            let result = baseDir.path.withCString { path in
                rac_model_paths_set_base_dir(path)
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.initializationFailed, "Failed to set base directory")
            }

            logger.debug("Base directory set to: \(baseDir.lastPathComponent)")
        }

        /// Get the configured base directory
        public static var baseDirectory: URL? {
            guard let ptr = rac_model_paths_get_base_dir() else { return nil }
            return URL(fileURLWithPath: String(cString: ptr))
        }

        // MARK: - Directory Paths

        /// Get the models directory
        /// Returns: `{base_dir}/RunAnywhere/Models/`
        public static func getModelsDirectory() throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = rac_model_paths_get_models_directory(&buffer, buffer.count)

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.initializationFailed, "Base directory not configured")
            }

            return URL(fileURLWithPath: String(cString: buffer))
        }

        /// Get the framework directory
        /// Returns: `{base_dir}/RunAnywhere/Models/{framework}/`
        public static func getFrameworkDirectory(framework: InferenceFramework) throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = rac_model_paths_get_framework_directory(framework.toCFramework(), &buffer, buffer.count)

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.initializationFailed, "Base directory not configured")
            }

            return URL(fileURLWithPath: String(cString: buffer))
        }

        /// Get the model folder
        /// Returns: `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
        public static func getModelFolder(modelId: String, framework: InferenceFramework) throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = modelId.withCString { mid in
                rac_model_paths_get_model_folder(mid, framework.toCFramework(), &buffer, buffer.count)
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.initializationFailed, "Base directory not configured")
            }

            return URL(fileURLWithPath: String(cString: buffer))
        }

        /// Get the expected model path (folder for directory-based, file for single-file)
        public static func getExpectedModelPath(
            modelId: String,
            framework: InferenceFramework,
            format: ModelFormat
        ) throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = modelId.withCString { mid in
                rac_model_paths_get_expected_model_path(
                    mid,
                    framework.toCFramework(),
                    format.toC(),
                    &buffer,
                    buffer.count
                )
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.initializationFailed, "Base directory not configured")
            }

            return URL(fileURLWithPath: String(cString: buffer))
        }

        /// Get the cache directory
        public static func getCacheDirectory() throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = rac_model_paths_get_cache_directory(&buffer, buffer.count)

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.initializationFailed, "Base directory not configured")
            }

            return URL(fileURLWithPath: String(cString: buffer))
        }

        /// Get the downloads directory
        public static func getDownloadsDirectory() throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = rac_model_paths_get_downloads_directory(&buffer, buffer.count)

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.initializationFailed, "Base directory not configured")
            }

            return URL(fileURLWithPath: String(cString: buffer))
        }

        /// Get the temp directory
        public static func getTempDirectory() throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = rac_model_paths_get_temp_directory(&buffer, buffer.count)

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.initializationFailed, "Base directory not configured")
            }

            return URL(fileURLWithPath: String(cString: buffer))
        }

        // MARK: - Path Analysis

        /// Extract model ID from a file path
        public static func extractModelId(from path: URL) -> String? {
            var buffer = [CChar](repeating: 0, count: 256)
            let result = path.path.withCString { pathPtr in
                rac_model_paths_extract_model_id(pathPtr, &buffer, buffer.count)
            }

            guard result == RAC_SUCCESS else { return nil }
            return String(cString: buffer)
        }

        /// Extract framework from a file path
        public static func extractFramework(from path: URL) -> InferenceFramework? {
            var framework: rac_inference_framework_t = RAC_FRAMEWORK_UNKNOWN
            let result = path.path.withCString { pathPtr in
                rac_model_paths_extract_framework(pathPtr, &framework)
            }

            guard result == RAC_SUCCESS else { return nil }
            return InferenceFramework(from: framework)
        }

        /// Check if a path is within the models directory
        public static func isModelPath(_ path: URL) -> Bool {
            return path.path.withCString { pathPtr in
                rac_model_paths_is_model_path(pathPtr) == RAC_TRUE
            }
        }
    }
}

// Note: InferenceFramework.toCFramework() is defined in InferenceFramework.swift
// Note: ModelFormat.toC() is defined in ModelTypes+CppBridge.swift
