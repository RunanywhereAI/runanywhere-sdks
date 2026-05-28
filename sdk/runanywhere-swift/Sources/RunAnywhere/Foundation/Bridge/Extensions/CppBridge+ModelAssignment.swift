//
//  CppBridge+ModelAssignment.swift
//  RunAnywhere SDK
//
//  Bridge for C++ model assignment manager.
//  All business logic (caching, JSON parsing, registry saving) is in C++.
//  Swift provides HTTP GET callback and device info.
//

import CRACommons
import Foundation

// MARK: - CppBridge Model Assignment Extension

public extension CppBridge {

    /// Model assignment bridge - fetches model assignments from backend
    enum ModelAssignment {

        private static let logger = SDKLogger(category: "CppBridge.ModelAssignment")
        private static var isRegistered = false
        private static let responseStorage = AssignmentResponseStorage()

        // MARK: - Registration

        /// Register callbacks with C++ model assignment manager
        /// Called during SDK initialization
        /// - Parameter autoFetch: Whether to auto-fetch models after registration.
        ///                        Should be false for development mode, true for staging/production.
        static func register(autoFetch: Bool = false) {
            guard !isRegistered else { return }

            var callbacks = rac_assignment_callbacks_t()

            // HTTP GET callback
            callbacks.http_get = { endpoint, requiresAuth, outResponse, userData -> rac_result_t in
                guard let endpoint = endpoint,
                      let outResponse = outResponse,
                      let userData = userData else {
                    return RAC_ERROR_NULL_POINTER
                }

                let storage = Unmanaged<AssignmentResponseStorage>.fromOpaque(userData).takeUnretainedValue()
                // Free the strings handed to commons on the previous fetch; commons
                // is done with them by the time it calls back in.
                storage.reset()

                let endpointStr = String(cString: endpoint)

                // Use semaphore to make async call synchronous for C callback
                let semaphore = DispatchSemaphore(value: 0)
                var result: rac_result_t = RAC_ERROR_HTTP_REQUEST_FAILED

                Task {
                    do {
                        let data: Data = try await CppBridge.HTTP.shared.getRaw(
                            endpointStr,
                            requiresAuth: requiresAuth == RAC_TRUE
                        )

                        let responseStr = String(data: data, encoding: .utf8) ?? ""
                        storage.responseBody = responseStr.withCString { strdup($0) }
                        outResponse.pointee.response_body = UnsafePointer(storage.responseBody)
                        outResponse.pointee.response_length = data.count
                        outResponse.pointee.status_code = 200
                        outResponse.pointee.result = RAC_SUCCESS
                        outResponse.pointee.error_message = nil
                        result = RAC_SUCCESS
                    } catch {
                        let errorMsg = error.localizedDescription
                        storage.errorMessage = errorMsg.withCString { strdup($0) }
                        outResponse.pointee.error_message = UnsafePointer(storage.errorMessage)
                        outResponse.pointee.result = RAC_ERROR_HTTP_REQUEST_FAILED
                        outResponse.pointee.status_code = 0
                        outResponse.pointee.response_body = nil
                        outResponse.pointee.response_length = 0
                        result = RAC_ERROR_HTTP_REQUEST_FAILED
                    }
                    semaphore.signal()
                }

                _ = semaphore.wait(timeout: .now() + 30)
                return result
            }

            callbacks.user_data = Unmanaged.passUnretained(responseStorage).toOpaque()
            // Only auto-fetch in staging/production, not development
            callbacks.auto_fetch = autoFetch ? RAC_TRUE : RAC_FALSE

            let result = rac_model_assignment_set_callbacks(&callbacks)
            if result == RAC_SUCCESS {
                isRegistered = true
                logger.debug("Model assignment callbacks registered (autoFetch: \(autoFetch))")
            } else {
                logger.error("Failed to register model assignment callbacks: \(result)")
            }
        }

        // MARK: - Public API

        /// Fetch model assignments from backend
        /// - Parameter forceRefresh: Force refresh even if cached
        /// - Returns: Array of generated model metadata records.
        public static func fetch(forceRefresh: Bool = false) async throws -> [RAModelInfo] {
            var outModels: UnsafeMutablePointer<UnsafeMutablePointer<rac_model_info_t>?>?
            var outCount: Int = 0

            let result = rac_model_assignment_fetch(
                forceRefresh ? RAC_TRUE : RAC_FALSE,
                &outModels,
                &outCount
            )

            guard result == RAC_SUCCESS else {
                throw SDKException(code: .httpError, message: "Failed to fetch model assignments: \(result)", category: .network)
            }

            defer {
                if let models = outModels {
                    rac_model_info_array_free(models, outCount)
                }
            }

            var modelInfos: [RAModelInfo] = []
            if let models = outModels {
                for i in 0..<outCount {
                    if let modelPtr = models[i] {
                        modelInfos.append(RAModelInfo(from: modelPtr.pointee))
                    }
                }
            }

            logger.info("Fetched \(modelInfos.count) model assignments")
            return modelInfos
        }

        /// Get cached models for a specific framework
        public static func getByFramework(_ framework: InferenceFramework) -> [RAModelInfo] {
            var outModels: UnsafeMutablePointer<UnsafeMutablePointer<rac_model_info_t>?>?
            var outCount: Int = 0

            let result = rac_model_assignment_get_by_framework(
                framework.toCFramework(),
                &outModels,
                &outCount
            )

            guard result == RAC_SUCCESS else {
                logger.warning("Failed to get models by framework: \(result)")
                return []
            }

            defer {
                if let models = outModels {
                    rac_model_info_array_free(models, outCount)
                }
            }

            var modelInfos: [RAModelInfo] = []
            if let models = outModels {
                for i in 0..<outCount {
                    if let modelPtr = models[i] {
                        modelInfos.append(RAModelInfo(from: modelPtr.pointee))
                    }
                }
            }

            return modelInfos
        }

        /// Get cached models for a specific category
        public static func getByCategory(_ category: ModelCategory) -> [RAModelInfo] {
            var outModels: UnsafeMutablePointer<UnsafeMutablePointer<rac_model_info_t>?>?
            var outCount: Int = 0

            let cCategory = categoryToCType(category)
            let result = rac_model_assignment_get_by_category(
                cCategory,
                &outModels,
                &outCount
            )

            guard result == RAC_SUCCESS else {
                logger.warning("Failed to get models by category: \(result)")
                return []
            }

            defer {
                if let models = outModels {
                    rac_model_info_array_free(models, outCount)
                }
            }

            var modelInfos: [RAModelInfo] = []
            if let models = outModels {
                for i in 0..<outCount {
                    if let modelPtr = models[i] {
                        modelInfos.append(RAModelInfo(from: modelPtr.pointee))
                    }
                }
            }

            return modelInfos
        }

        // MARK: - Private Helpers

        private static func categoryToCType(_ category: ModelCategory) -> rac_model_category_t {
            category.toC()
        }
    }
}

/// Owns the C strings handed to commons via the assignment http_get response.
///
/// The `rac_assignment_http_response_t` body/error pointers are produced by Swift
/// (`strdup`) but only read by commons during the synchronous http_get call; commons
/// never frees them. We retain the last allocation here (reachable from
/// `callbacks.user_data`) and free it at the start of the next callback, so each fetch
/// reuses one slot instead of leaking. Commons serializes http_get under its own mutex,
/// so accessing this storage from the callback is race-free.
private final class AssignmentResponseStorage {
    var responseBody: UnsafeMutablePointer<CChar>?
    var errorMessage: UnsafeMutablePointer<CChar>?

    func reset() {
        free(responseBody)
        free(errorMessage)
        responseBody = nil
        errorMessage = nil
    }
}
