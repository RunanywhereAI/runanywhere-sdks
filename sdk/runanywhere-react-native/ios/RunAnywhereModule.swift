/**
 * RunAnywhere React Native SDK - iOS Native Module
 *
 * This module bridges the RunAnywhere Swift SDK to React Native.
 * It wraps the existing Swift SDK and exposes its functionality to JavaScript.
 */

import Foundation
import React
// Import the RunAnywhere Swift SDK
// Note: This import will work when the SDK is properly linked via CocoaPods
#if canImport(RunAnywhere)
import RunAnywhere
#endif

@objc(RunAnywhereModule)
class RunAnywhereModule: RCTEventEmitter {

    // MARK: - Event Names

    private enum EventName: String, CaseIterable {
        case sdkInitialization = "RunAnywhere_SDKInitialization"
        case sdkConfiguration = "RunAnywhere_SDKConfiguration"
        case sdkGeneration = "RunAnywhere_SDKGeneration"
        case sdkModel = "RunAnywhere_SDKModel"
        case sdkVoice = "RunAnywhere_SDKVoice"
        case sdkPerformance = "RunAnywhere_SDKPerformance"
        case sdkNetwork = "RunAnywhere_SDKNetwork"
        case sdkStorage = "RunAnywhere_SDKStorage"
        case sdkFramework = "RunAnywhere_SDKFramework"
        case sdkDevice = "RunAnywhere_SDKDevice"
        case sdkComponent = "RunAnywhere_SDKComponent"
        case allEvents = "RunAnywhere_AllEvents"
    }

    // MARK: - RCTEventEmitter

    override func supportedEvents() -> [String]! {
        return EventName.allCases.map { $0.rawValue }
    }

    override static func requiresMainQueueSetup() -> Bool {
        return false
    }

    // MARK: - Event Subscriptions

    private var cancellables: [Any] = []

    override init() {
        super.init()
        setupEventSubscriptions()
    }

    private func setupEventSubscriptions() {
        #if canImport(RunAnywhere)
        // Subscribe to SDK events and forward to React Native
        // This will be implemented when the SDK is properly linked

        // Example subscription pattern (to be implemented):
        // cancellables.append(
        //     RunAnywhere.events.onGeneration { [weak self] event in
        //         self?.sendEvent(withName: EventName.sdkGeneration.rawValue, body: event.toDict())
        //     }
        // )
        #endif
    }

    // MARK: - Initialization

    @objc(initialize:baseURL:environment:resolver:rejecter:)
    func initialize(
        _ apiKey: String,
        baseURL: String,
        environment: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                let env = SDKEnvironment(rawValue: environment) ?? .production
                try RunAnywhere.initialize(apiKey: apiKey, baseURL: baseURL, environment: env)
                resolve(nil)
            } catch {
                reject("INIT_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(reset:rejecter:)
    func reset(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        RunAnywhere.reset()
        resolve(nil)
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(isInitialized:rejecter:)
    func isInitialized(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        resolve(RunAnywhere.isSDKInitialized)
        #else
        resolve(false)
        #endif
    }

    @objc(isActive:rejecter:)
    func isActive(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        resolve(RunAnywhere.isActive())
        #else
        resolve(false)
        #endif
    }

    // MARK: - Identity

    @objc(getUserId:rejecter:)
    func getUserId(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            let userId = await RunAnywhere.getUserId()
            resolve(userId)
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(getOrganizationId:rejecter:)
    func getOrganizationId(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            let orgId = await RunAnywhere.getOrganizationId()
            resolve(orgId)
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(getDeviceId:rejecter:)
    func getDeviceId(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            let deviceId = await RunAnywhere.getDeviceId()
            resolve(deviceId)
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(getSDKVersion:rejecter:)
    func getSDKVersion(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        resolve(RunAnywhere.getSDKVersion())
        #else
        resolve("0.0.0")
        #endif
    }

    @objc(getCurrentEnvironment:rejecter:)
    func getCurrentEnvironment(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        resolve(RunAnywhere.getCurrentEnvironment()?.rawValue)
        #else
        resolve(nil)
        #endif
    }

    @objc(isDeviceRegistered:rejecter:)
    func isDeviceRegistered(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        resolve(RunAnywhere.isDeviceRegistered())
        #else
        resolve(false)
        #endif
    }

    // MARK: - Text Generation

    @objc(chat:resolver:rejecter:)
    func chat(
        _ prompt: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                let response = try await RunAnywhere.chat(prompt)
                resolve(response)
            } catch {
                reject("GENERATION_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(generate:options:resolver:rejecter:)
    func generate(
        _ prompt: String,
        options: NSDictionary?,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                let genOptions = parseGenerationOptions(options)
                let result = try await RunAnywhere.generate(prompt, options: genOptions)
                resolve(generationResultToDict(result))
            } catch {
                reject("GENERATION_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(generateStreamStart:options:resolver:rejecter:)
    func generateStreamStart(
        _ prompt: String,
        options: NSDictionary?,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        // Generate a session ID
        let sessionId = UUID().uuidString

        Task {
            do {
                let genOptions = parseGenerationOptions(options)
                let streamingResult = try await RunAnywhere.generateStream(prompt, options: genOptions)

                // Process stream and emit events
                Task {
                    do {
                        for try await token in streamingResult.stream {
                            self.sendEvent(withName: EventName.sdkGeneration.rawValue, body: [
                                "type": "tokenGenerated",
                                "token": token,
                                "sessionId": sessionId
                            ])
                        }

                        // Get final result
                        let finalResult = try await streamingResult.result.value
                        self.sendEvent(withName: EventName.sdkGeneration.rawValue, body: [
                            "type": "completed",
                            "response": finalResult.text,
                            "tokensUsed": finalResult.tokensUsed,
                            "latencyMs": finalResult.latencyMs,
                            "sessionId": sessionId
                        ])
                    } catch {
                        self.sendEvent(withName: EventName.sdkGeneration.rawValue, body: [
                            "type": "failed",
                            "error": error.localizedDescription,
                            "sessionId": sessionId
                        ])
                    }
                }

                resolve(sessionId)
            } catch {
                reject("STREAM_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(generateStreamCancel:resolver:rejecter:)
    func generateStreamCancel(
        _ sessionId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        // TODO: Implement stream cancellation
        resolve(nil)
    }

    // MARK: - Model Management

    @objc(loadModel:resolver:rejecter:)
    func loadModel(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                try await RunAnywhere.loadModel(modelId)
                resolve(nil)
            } catch {
                reject("LOAD_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(availableModels:rejecter:)
    func availableModels(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                let models = try await RunAnywhere.availableModels()
                let modelsArray = models.map { modelInfoToDict($0) }
                resolve(modelsArray)
            } catch {
                reject("MODELS_ERROR", error.localizedDescription, error)
            }
        }
        #else
        resolve([])
        #endif
    }

    @objc(currentModel:rejecter:)
    func currentModel(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        if let model = RunAnywhere.currentModel {
            resolve(modelInfoToDict(model))
        } else {
            resolve(nil)
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(downloadModel:resolver:rejecter:)
    func downloadModel(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        // TODO: Implement model download
        reject("NOT_IMPLEMENTED", "Model download not yet implemented", nil)
    }

    @objc(deleteModel:resolver:rejecter:)
    func deleteModel(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        // TODO: Implement model deletion
        reject("NOT_IMPLEMENTED", "Model deletion not yet implemented", nil)
    }

    @objc(availableAdapters:resolver:rejecter:)
    func availableAdapters(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            let adapters = await RunAnywhere.availableAdapters(for: modelId)
            resolve(adapters.map { $0.rawValue })
        }
        #else
        resolve([])
        #endif
    }

    // MARK: - Voice Operations

    @objc(transcribe:options:resolver:rejecter:)
    func transcribe(
        _ audioBase64: String,
        options: NSDictionary?,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                guard let audioData = Data(base64Encoded: audioBase64) else {
                    reject("INVALID_AUDIO", "Invalid base64 audio data", nil)
                    return
                }

                let transcript = try await RunAnywhere.transcribe(audioData)
                resolve([
                    "text": transcript,
                    "segments": [],
                    "confidence": 1.0,
                    "duration": 0,
                    "alternatives": []
                ])
            } catch {
                reject("TRANSCRIBE_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(loadSTTModel:resolver:rejecter:)
    func loadSTTModel(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                try await RunAnywhere.loadSTTModel(modelId)
                resolve(nil)
            } catch {
                reject("LOAD_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(loadTTSModel:resolver:rejecter:)
    func loadTTSModel(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                try await RunAnywhere.loadTTSModel(modelId)
                resolve(nil)
            } catch {
                reject("LOAD_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(synthesize:configuration:resolver:rejecter:)
    func synthesize(
        _ text: String,
        configuration: NSDictionary?,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        // TODO: Implement TTS synthesis
        reject("NOT_IMPLEMENTED", "TTS synthesis not yet implemented", nil)
    }

    // MARK: - Utilities

    @objc(estimateTokenCount:resolver:rejecter:)
    func estimateTokenCount(
        _ text: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        resolve(RunAnywhere.estimateTokenCount(text))
        #else
        // Simple estimation: ~4 chars per token
        resolve(text.count / 4)
        #endif
    }

    // MARK: - Configuration Service

    @objc(getConfiguration:rejecter:)
    func getConfiguration(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            let config = await ServiceContainer.shared.configurationService.getConfiguration()
            resolve(config.map { configurationToDict($0) })
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(loadConfigurationOnLaunch:resolver:rejecter:)
    func loadConfigurationOnLaunch(
        _ apiKey: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            let config = await ServiceContainer.shared.configurationService.loadConfigurationOnLaunch(apiKey: apiKey)
            resolve(configurationToDict(config))
        }
        #else
        resolve([:])
        #endif
    }

    @objc(setConsumerConfiguration:resolver:rejecter:)
    func setConsumerConfiguration(
        _ config: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                // Parse consumer config and set it
                // This is a simplified implementation
                resolve(nil)
            } catch {
                reject("CONFIG_ERROR", error.localizedDescription, error)
            }
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(updateConfiguration:options:resolver:rejecter:)
    func updateConfiguration(
        _ updates: NSDictionary,
        options: NSDictionary?,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            // Update configuration
            resolve(nil)
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(syncConfigurationToCloud:rejecter:)
    func syncConfigurationToCloud(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                try await ServiceContainer.shared.configurationService.syncToCloud()
                resolve(nil)
            } catch {
                reject("SYNC_ERROR", error.localizedDescription, error)
            }
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(clearConfigurationCache:rejecter:)
    func clearConfigurationCache(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                try await ServiceContainer.shared.configurationService.clearCache()
                resolve(nil)
            } catch {
                reject("CACHE_ERROR", error.localizedDescription, error)
            }
        }
        #else
        resolve(nil)
        #endif
    }

    // MARK: - Authentication Service

    @objc(authenticate:resolver:rejecter:)
    func authenticate(
        _ apiKey: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                let response = try await ServiceContainer.shared.authenticationService.authenticate(apiKey: apiKey)
                resolve([
                    "accessToken": response.accessToken,
                    "refreshToken": response.refreshToken,
                    "expiresIn": response.expiresIn,
                    "deviceId": response.deviceId,
                    "userId": response.userId as Any,
                    "organizationId": response.organizationId
                ])
            } catch {
                reject("AUTH_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(getAccessToken:rejecter:)
    func getAccessToken(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                let token = try await ServiceContainer.shared.authenticationService.getAccessToken()
                resolve(token)
            } catch {
                reject("TOKEN_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(refreshAccessToken:rejecter:)
    func refreshAccessToken(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                let token = try await ServiceContainer.shared.authenticationService.getAccessToken()
                resolve(token)
            } catch {
                reject("TOKEN_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(isAuthenticated:rejecter:)
    func isAuthenticated(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            let isAuth = await ServiceContainer.shared.authenticationService.isAuthenticated()
            resolve(isAuth)
        }
        #else
        resolve(false)
        #endif
    }

    @objc(clearAuthentication:rejecter:)
    func clearAuthentication(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                try await ServiceContainer.shared.authenticationService.clearAuthentication()
                resolve(nil)
            } catch {
                reject("AUTH_ERROR", error.localizedDescription, error)
            }
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(loadStoredTokens:rejecter:)
    func loadStoredTokens(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                try await ServiceContainer.shared.authenticationService.loadStoredTokens()
                resolve(nil)
            } catch {
                reject("TOKEN_ERROR", error.localizedDescription, error)
            }
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(registerDevice:rejecter:)
    func registerDevice(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                let response = try await ServiceContainer.shared.authenticationService.registerDevice()
                resolve(["deviceId": response.deviceId])
            } catch {
                reject("REGISTER_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(healthCheck:rejecter:)
    func healthCheck(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                let response = try await ServiceContainer.shared.authenticationService.healthCheck()
                resolve([
                    "status": response.status,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ])
            } catch {
                reject("HEALTH_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    // MARK: - Model Registry

    @objc(initializeRegistry:resolver:rejecter:)
    func initializeRegistry(
        _ apiKey: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            await ServiceContainer.shared.modelRegistry.initialize(with: apiKey)
            resolve(nil)
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(discoverModels:rejecter:)
    func discoverModels(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            let models = await ServiceContainer.shared.modelRegistry.discoverModels()
            resolve(models.map { modelInfoToDict($0) })
        }
        #else
        resolve([])
        #endif
    }

    @objc(registerModel:resolver:rejecter:)
    func registerModel(
        _ model: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        // Parse model from dict and register
        resolve(nil)
        #else
        resolve(nil)
        #endif
    }

    @objc(registerModelPersistently:resolver:rejecter:)
    func registerModelPersistently(
        _ model: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            // Parse model from dict and register persistently
            resolve(nil)
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(getModel:resolver:rejecter:)
    func getModel(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        if let model = ServiceContainer.shared.modelRegistry.getModel(by: modelId) {
            resolve(modelInfoToDict(model))
        } else {
            resolve(nil)
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(filterModels:resolver:rejecter:)
    func filterModels(
        _ criteria: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        // Parse criteria and filter models
        let modelCriteria = ModelCriteria()
        let models = ServiceContainer.shared.modelRegistry.filterModels(by: modelCriteria)
        resolve(models.map { modelInfoToDict($0) })
        #else
        resolve([])
        #endif
    }

    @objc(updateModel:resolver:rejecter:)
    func updateModel(
        _ model: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        // Parse model and update
        resolve(nil)
        #else
        resolve(nil)
        #endif
    }

    @objc(removeModel:resolver:rejecter:)
    func removeModel(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        ServiceContainer.shared.modelRegistry.removeModel(modelId)
        resolve(nil)
        #else
        resolve(nil)
        #endif
    }

    @objc(addModelFromURL:resolver:rejecter:)
    func addModelFromURL(
        _ options: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        guard let name = options["name"] as? String,
              let urlString = options["url"] as? String,
              let url = URL(string: urlString),
              let frameworkStr = options["framework"] as? String,
              let framework = LLMFramework(rawValue: frameworkStr) else {
            reject("INVALID_OPTIONS", "Invalid options for addModelFromURL", nil)
            return
        }

        let model = ServiceContainer.shared.modelRegistry.addModelFromURL(
            name: name,
            url: url,
            framework: framework,
            estimatedSize: options["estimatedSize"] as? Int64,
            supportsThinking: options["supportsThinking"] as? Bool ?? false
        )
        resolve(modelInfoToDict(model))
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    // MARK: - Download Service

    @objc(startModelDownload:resolver:rejecter:)
    func startModelDownload(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            do {
                guard let model = ServiceContainer.shared.modelRegistry.getModel(by: modelId) else {
                    reject("MODEL_NOT_FOUND", "Model not found: \(modelId)", nil)
                    return
                }

                let task = try await ServiceContainer.shared.downloadManager.downloadModel(model)

                // Emit download started event
                self.sendEvent(withName: EventName.sdkModel.rawValue, body: [
                    "type": "downloadStarted",
                    "modelId": modelId,
                    "taskId": task.id
                ])

                // Start progress tracking
                Task {
                    for await progress in task.progress {
                        self.sendEvent(withName: EventName.sdkModel.rawValue, body: [
                            "type": "downloadProgress",
                            "modelId": modelId,
                            "taskId": task.id,
                            "bytesDownloaded": progress.bytesDownloaded,
                            "totalBytes": progress.totalBytes,
                            "progress": Double(progress.bytesDownloaded) / Double(max(progress.totalBytes, 1)),
                            "downloadState": progress.state.description
                        ])
                    }
                }

                // Wait for completion
                Task {
                    do {
                        let localPath = try await task.result.value
                        self.sendEvent(withName: EventName.sdkModel.rawValue, body: [
                            "type": "downloadCompleted",
                            "modelId": modelId,
                            "taskId": task.id,
                            "localPath": localPath.path
                        ])
                    } catch {
                        self.sendEvent(withName: EventName.sdkModel.rawValue, body: [
                            "type": "downloadFailed",
                            "modelId": modelId,
                            "taskId": task.id,
                            "error": error.localizedDescription
                        ])
                    }
                }

                resolve(task.id)
            } catch {
                reject("DOWNLOAD_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    @objc(cancelDownload:resolver:rejecter:)
    func cancelDownload(
        _ taskId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        ServiceContainer.shared.downloadManager.cancelDownload(taskId: taskId)
        resolve(nil)
        #else
        resolve(nil)
        #endif
    }

    @objc(pauseDownload:resolver:rejecter:)
    func pauseDownload(
        _ taskId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        ServiceContainer.shared.downloadManager.pauseAll()
        resolve(nil)
        #else
        resolve(nil)
        #endif
    }

    @objc(resumeDownload:resolver:rejecter:)
    func resumeDownload(
        _ taskId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        ServiceContainer.shared.downloadManager.resumeAll()
        resolve(nil)
        #else
        resolve(nil)
        #endif
    }

    @objc(pauseAllDownloads:rejecter:)
    func pauseAllDownloads(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        ServiceContainer.shared.downloadManager.pauseAll()
        resolve(nil)
        #else
        resolve(nil)
        #endif
    }

    @objc(resumeAllDownloads:rejecter:)
    func resumeAllDownloads(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        ServiceContainer.shared.downloadManager.resumeAll()
        resolve(nil)
        #else
        resolve(nil)
        #endif
    }

    @objc(cancelAllDownloads:rejecter:)
    func cancelAllDownloads(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        // Cancel all active downloads
        resolve(nil)
        #else
        resolve(nil)
        #endif
    }

    @objc(getDownloadProgress:resolver:rejecter:)
    func getDownloadProgress(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        // Return current download progress for model
        resolve(nil)
    }

    @objc(configureDownloadService:resolver:rejecter:)
    func configureDownloadService(
        _ config: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        // Configure download service
        resolve(nil)
    }

    @objc(isDownloadServiceHealthy:rejecter:)
    func isDownloadServiceHealthy(
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        resolve(ServiceContainer.shared.downloadManager.isHealthy())
        #else
        resolve(true)
        #endif
    }

    @objc(getDownloadResumeData:resolver:rejecter:)
    func getDownloadResumeData(
        _ modelId: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        if let resumeData = ServiceContainer.shared.downloadManager.getResumeData(for: modelId) {
            resolve(resumeData.base64EncodedString())
        } else {
            resolve(nil)
        }
        #else
        resolve(nil)
        #endif
    }

    @objc(resumeDownloadWithData:resumeData:resolver:rejecter:)
    func resumeDownloadWithData(
        _ modelId: String,
        resumeData: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        #if canImport(RunAnywhere)
        Task {
            guard let model = ServiceContainer.shared.modelRegistry.getModel(by: modelId),
                  let data = Data(base64Encoded: resumeData) else {
                reject("INVALID_DATA", "Invalid model or resume data", nil)
                return
            }

            do {
                let task = try await ServiceContainer.shared.downloadManager.downloadModelWithResume(model, resumeData: data)
                resolve(task.id)
            } catch {
                reject("DOWNLOAD_ERROR", error.localizedDescription, error)
            }
        }
        #else
        reject("NOT_AVAILABLE", "RunAnywhere SDK not available", nil)
        #endif
    }

    // MARK: - Helper Methods

    #if canImport(RunAnywhere)
    private func parseGenerationOptions(_ options: NSDictionary?) -> RunAnywhereGenerationOptions {
        guard let opts = options else {
            return RunAnywhereGenerationOptions()
        }

        return RunAnywhereGenerationOptions(
            maxTokens: opts["maxTokens"] as? Int ?? 100,
            temperature: (opts["temperature"] as? NSNumber)?.floatValue ?? 0.7,
            topP: (opts["topP"] as? NSNumber)?.floatValue ?? 1.0,
            enableRealTimeTracking: opts["enableRealTimeTracking"] as? Bool ?? true,
            stopSequences: opts["stopSequences"] as? [String] ?? [],
            streamingEnabled: opts["streamingEnabled"] as? Bool ?? false,
            preferredExecutionTarget: nil,
            preferredFramework: nil,
            structuredOutput: nil,
            systemPrompt: opts["systemPrompt"] as? String
        )
    }

    private func generationResultToDict(_ result: GenerationResult) -> [String: Any] {
        var dict: [String: Any] = [
            "text": result.text,
            "tokensUsed": result.tokensUsed,
            "modelUsed": result.modelUsed,
            "latencyMs": result.latencyMs,
            "executionTarget": result.executionTarget.rawValue,
            "savedAmount": result.savedAmount,
            "hardwareUsed": result.hardwareUsed.rawValue,
            "memoryUsed": result.memoryUsed,
            "responseTokens": result.responseTokens,
            "performanceMetrics": [
                "timeToFirstTokenMs": result.performanceMetrics.timeToFirstTokenMs as Any,
                "tokensPerSecond": result.performanceMetrics.tokensPerSecond as Any,
                "inferenceTimeMs": result.performanceMetrics.inferenceTimeMs
            ]
        ]

        if let thinking = result.thinkingContent {
            dict["thinkingContent"] = thinking
        }

        if let framework = result.framework {
            dict["framework"] = framework.rawValue
        }

        if let thinkingTokens = result.thinkingTokens {
            dict["thinkingTokens"] = thinkingTokens
        }

        return dict
    }

    private func configurationToDict(_ config: ConfigurationData) -> [String: Any] {
        var dict: [String: Any] = [
            "apiKey": config.apiKey,
            "baseURL": config.baseURL,
            "environment": config.environment.rawValue,
            "source": config.source.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: config.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: config.updatedAt),
            "syncPending": config.syncPending
        ]

        if let routingPolicy = config.routingPolicy {
            dict["routingPolicy"] = routingPolicy.rawValue
        }

        if let privacyMode = config.privacyMode {
            dict["privacyMode"] = privacyMode.rawValue
        }

        if let telemetryEnabled = config.telemetryEnabled {
            dict["telemetryEnabled"] = telemetryEnabled
        }

        return dict
    }

    private func modelInfoToDict(_ model: ModelInfo) -> [String: Any] {
        var dict: [String: Any] = [
            "id": model.id,
            "name": model.name,
            "category": model.category.rawValue,
            "format": model.format.rawValue,
            "compatibleFrameworks": model.compatibleFrameworks.map { $0.rawValue },
            "supportsThinking": model.supportsThinking,
            "source": model.source.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: model.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: model.updatedAt),
            "syncPending": model.syncPending,
            "usageCount": model.usageCount,
            "isDownloaded": model.isDownloaded,
            "isAvailable": model.isAvailable
        ]

        if let downloadURL = model.downloadURL {
            dict["downloadURL"] = downloadURL.absoluteString
        }

        if let localPath = model.localPath {
            dict["localPath"] = localPath.path
        }

        if let downloadSize = model.downloadSize {
            dict["downloadSize"] = downloadSize
        }

        if let memoryRequired = model.memoryRequired {
            dict["memoryRequired"] = memoryRequired
        }

        if let preferredFramework = model.preferredFramework {
            dict["preferredFramework"] = preferredFramework.rawValue
        }

        if let contextLength = model.contextLength {
            dict["contextLength"] = contextLength
        }

        if let lastUsed = model.lastUsed {
            dict["lastUsed"] = ISO8601DateFormatter().string(from: lastUsed)
        }

        return dict
    }
    #endif
}
