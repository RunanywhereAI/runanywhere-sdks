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

        private static func decodeCStringBuffer(_ buffer: [CChar]) -> String {
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return String(bytes: bytes, encoding: .utf8) ?? ""
        }

        // MARK: - Configuration

        /// Set the base directory for model storage
        /// Must be called during SDK initialization
        public static func setBaseDirectory(_ baseDir: URL) throws {
            let result = baseDir.path.withCString { path in
                rac_model_paths_set_base_dir(path)
            }

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .initializationFailed, message: "Failed to set base directory", category: .internal)
            }

            // Log the full absolute path (not lastPathComponent) so we can verify
            // the C++ side actually received "/var/mobile/.../Documents" and not
            // just the literal "Documents" — the latter was the red flag in the
            // 2nd-launch persistence regression.
            logger.debug("Base directory set to: \(baseDir.path)")
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
                throw SDKException(code: .initializationFailed, message: "Base directory not configured", category: .internal)
            }

            return URL(fileURLWithPath: decodeCStringBuffer(buffer))
        }

        /// Get the framework directory
        /// Returns: `{base_dir}/RunAnywhere/Models/{framework}/`
        public static func getFrameworkDirectory(framework: InferenceFramework) throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = rac_model_paths_get_framework_directory(framework.toCFramework(), &buffer, buffer.count)

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .initializationFailed, message: "Base directory not configured", category: .internal)
            }

            return URL(fileURLWithPath: decodeCStringBuffer(buffer))
        }

        /// Get the model folder
        /// Returns: `{base_dir}/RunAnywhere/Models/{framework}/{modelId}/`
        public static func getModelFolder(modelId: String, framework: InferenceFramework) throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = modelId.withCString { mid in
                rac_model_paths_get_model_folder(mid, framework.toCFramework(), &buffer, buffer.count)
            }

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .initializationFailed, message: "Base directory not configured", category: .internal)
            }

            return URL(fileURLWithPath: decodeCStringBuffer(buffer))
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
                throw SDKException(code: .initializationFailed, message: "Base directory not configured", category: .internal)
            }

            return URL(fileURLWithPath: decodeCStringBuffer(buffer))
        }

        /// Get the cache directory
        public static func getCacheDirectory() throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = rac_model_paths_get_cache_directory(&buffer, buffer.count)

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .initializationFailed, message: "Base directory not configured", category: .internal)
            }

            return URL(fileURLWithPath: decodeCStringBuffer(buffer))
        }

        /// Get the downloads directory
        public static func getDownloadsDirectory() throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = rac_model_paths_get_downloads_directory(&buffer, buffer.count)

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .initializationFailed, message: "Base directory not configured", category: .internal)
            }

            return URL(fileURLWithPath: decodeCStringBuffer(buffer))
        }

        /// Get the temp directory
        public static func getTempDirectory() throws -> URL {
            var buffer = [CChar](repeating: 0, count: pathBufferSize)
            let result = rac_model_paths_get_temp_directory(&buffer, buffer.count)

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .initializationFailed, message: "Base directory not configured", category: .internal)
            }

            return URL(fileURLWithPath: decodeCStringBuffer(buffer))
        }

        // MARK: - Path Analysis

        /// Extract model ID from a file path
        public static func extractModelId(from path: URL) -> String? {
            var buffer = [CChar](repeating: 0, count: 256)
            let result = path.path.withCString { pathPtr in
                rac_model_paths_extract_model_id(pathPtr, &buffer, buffer.count)
            }

            guard result == RAC_SUCCESS else { return nil }
            return decodeCStringBuffer(buffer)
        }

        /// Extract framework from a file path
        public static func extractFramework(from path: URL) -> InferenceFramework? {
            var framework: rac_inference_framework_t = RAC_FRAMEWORK_UNKNOWN
            let result = path.path.withCString { pathPtr in
                rac_model_paths_extract_framework(pathPtr, &framework)
            }

            guard result == RAC_SUCCESS else { return nil }
            return InferenceFramework.fromCFramework(framework)
        }

        /// Check if a path is within the models directory
        public static func isModelPath(_ path: URL) -> Bool {
            return path.path.withCString { pathPtr in
                rac_model_paths_is_model_path(pathPtr) == RAC_TRUE
            }
        }

        // MARK: - File Role Inference

        /// Infer the canonical `RAModelFileRole` for a single sidecar filename.
        /// Delegates to commons `rac_infer_model_file_role` so the classification
        /// stays byte-identical with the C++ resolver and every other SDK.
        public static func inferFileRole(filename: String, modality: ModelCategory) -> RAModelFileRole {
            var roleProto = Int32(RAModelFileRole.primaryModel.rawValue)
            _ = filename.withCString { name in
                rac_infer_model_file_role(name, Int32(modality.rawValue), &roleProto)
            }
            return RAModelFileRole(rawValue: Int(roleProto)) ?? .primaryModel
        }
    }
}

// Note: InferenceFramework.toCFramework() is defined in InferenceFramework.swift
// Note: ModelFormat.toC() is defined in ModelTypes+CppBridge.swift
