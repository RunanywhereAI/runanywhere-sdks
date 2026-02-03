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

        // MARK: - Registration

        /// Register callbacks with C++ model assignment manager
        /// Called during SDK initialization
        /// - Parameter autoFetch: Whether to auto-fetch models after registration.
        ///                        Should be false for development mode, true for staging/production.
        static func register(autoFetch: Bool = false) {
            guard !isRegistered else { return }

            var callbacks = rac_assignment_callbacks_t()

            // HTTP GET callback
            callbacks.http_get = { endpoint, requiresAuth, outResponse, _ -> rac_result_t in
                guard let endpoint = endpoint,
                      let outResponse = outResponse else {
                    return RAC_ERROR_NULL_POINTER
                }

                let endpointStr = String(cString: endpoint)

                // Use semaphore to make async call synchronous for C callback
                let semaphore = DispatchSemaphore(value: 0)
                let resultPtr = UnsafeMutablePointer<rac_result_t>.allocate(capacity: 1)
                resultPtr.initialize(to: RAC_ERROR_HTTP_REQUEST_FAILED)
                // Temporary storage to avoid mutating captured outResponse inside Task (Swift 6 concurrency)
                let statusCodePtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
                let responseLengthPtr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
                let responseBodyPtr = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 1)
                let errorMessagePtr = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 1)
                statusCodePtr.initialize(to: 0)
                responseLengthPtr.initialize(to: 0)
                responseBodyPtr.initialize(to: nil)
                errorMessagePtr.initialize(to: nil)

                Task {
                    do {
                        let data: Data = try await CppBridge.HTTP.shared.getRaw(
                            endpointStr,
                            requiresAuth: requiresAuth == RAC_TRUE
                        )

                        // Store response body - C++ will copy it
                        let responseStr = String(data: data, encoding: .utf8) ?? ""
                        responseStr.withCString { cStr in
                            responseBodyPtr.pointee = strdup(cStr)
                        }
                        responseLengthPtr.pointee = data.count
                        statusCodePtr.pointee = 200
                        resultPtr.pointee = RAC_SUCCESS
                    } catch {
                        let errorMsg = error.localizedDescription
                        errorMsg.withCString { cStr in
                            errorMessagePtr.pointee = strdup(cStr)
                        }
                        statusCodePtr.pointee = 0
                        responseLengthPtr.pointee = 0
                        responseBodyPtr.pointee = nil
                        resultPtr.pointee = RAC_ERROR_HTTP_REQUEST_FAILED
                    }
                    semaphore.signal()
                }

                _ = semaphore.wait(timeout: .now() + 30)
                outResponse.pointee.result = resultPtr.pointee
                outResponse.pointee.status_code = statusCodePtr.pointee
                outResponse.pointee.response_length = responseLengthPtr.pointee
                outResponse.pointee.response_body = responseBodyPtr.pointee.map { UnsafePointer($0) }
                outResponse.pointee.error_message = errorMessagePtr.pointee.map { UnsafePointer($0) }
                resultPtr.deallocate()
                statusCodePtr.deallocate()
                responseLengthPtr.deallocate()
                responseBodyPtr.deallocate()
                errorMessagePtr.deallocate()
                return outResponse.pointee.result
            }

            callbacks.user_data = nil
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
        /// - Returns: Array of ModelInfo
        public static func fetch(forceRefresh: Bool = false) async throws -> [ModelInfo] {
            var outModels: UnsafeMutablePointer<UnsafeMutablePointer<rac_model_info_t>?>?
            var outCount: Int = 0

            let result = rac_model_assignment_fetch(
                forceRefresh ? RAC_TRUE : RAC_FALSE,
                &outModels,
                &outCount
            )

            guard result == RAC_SUCCESS else {
                throw SDKError.network(.httpError, "Failed to fetch model assignments: \(result)")
            }

            defer {
                if let models = outModels {
                    rac_model_info_array_free(models, outCount)
                }
            }

            var modelInfos: [ModelInfo] = []
            if let models = outModels {
                for i in 0..<outCount {
                    if let modelPtr = models[i] {
                        modelInfos.append(ModelInfo(from: modelPtr.pointee))
                    }
                }
            }

            logger.info("Fetched \(modelInfos.count) model assignments")
            return modelInfos
        }

        /// Get cached models for a specific framework
        public static func getByFramework(_ framework: InferenceFramework) -> [ModelInfo] {
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

            var modelInfos: [ModelInfo] = []
            if let models = outModels {
                for i in 0..<outCount {
                    if let modelPtr = models[i] {
                        modelInfos.append(ModelInfo(from: modelPtr.pointee))
                    }
                }
            }

            return modelInfos
        }

        /// Get cached models for a specific category
        public static func getByCategory(_ category: ModelCategory) -> [ModelInfo] {
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

            var modelInfos: [ModelInfo] = []
            if let models = outModels {
                for i in 0..<outCount {
                    if let modelPtr = models[i] {
                        modelInfos.append(ModelInfo(from: modelPtr.pointee))
                    }
                }
            }

            return modelInfos
        }

        // MARK: - Private Helpers

        private static func categoryToCType(_ category: ModelCategory) -> rac_model_category_t {
            switch category {
            case .language:
                return RAC_MODEL_CATEGORY_LANGUAGE
            case .speechRecognition:
                return RAC_MODEL_CATEGORY_SPEECH_RECOGNITION
            case .speechSynthesis:
                return RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS
            case .vision:
                return RAC_MODEL_CATEGORY_VISION
            case .imageGeneration:
                return RAC_MODEL_CATEGORY_IMAGE_GENERATION
            case .multimodal:
                return RAC_MODEL_CATEGORY_MULTIMODAL
            case .audio:
                return RAC_MODEL_CATEGORY_AUDIO
            }
        }
    }
}
