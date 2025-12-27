# Phase 3: Swift SDK Integration

**Duration**: 3 weeks
**Objective**: Refactor `runanywhere-swift` to consume the new modular XCFrameworks from `runanywhere-commons`.

---

## ⚠️ Key Design Decision: Swift as Orchestrator

### Problem Identified
Two parallel orchestration systems exist - Swift SDK has `ModuleRegistry.swift` + `ServiceRegistry.swift`, and the plan adds C++ versions.

### Solution: Swift SDK Remains the Orchestrator

The Swift SDK (`runanywhere-swift`) is the **most stable** and serves as the source of truth. The C++ commons layer provides **backend-level registration only**.

| Layer | Responsibility | Registry |
|-------|----------------|----------|
| **Swift SDK** | Service creation, capability routing, async APIs | `ModuleRegistry.swift`, `ServiceRegistry.swift` |
| **Commons (C++)** | Backend self-registration, event publishing | `rac_module_register`, `rac_event_publish` |

**Flow:**
1. App imports backend module: `import LlamaCPPRuntime`
2. Swift module's static init calls: `rac_backend_llamacpp_register()` → C++ registry
3. Swift `ModuleRegistry.register(LlamaCPP.self)` → Swift registry + factory
4. Service creation goes through Swift `ServiceRegistry` → Creates Swift service wrapper → Calls C++ backend

---

## ⚠️ Callback Adapter Pattern

### Problem Identified
New commons streaming callback has different signature than existing bridge callback.

### Solution: Adapter Pattern in Swift

```swift
// Old bridge callback (ra_types.h):
// typedef bool (*ra_text_stream_callback)(const char* token, void* user_data);

// New commons callback (rac_llm_llamacpp.h):
// typedef void (*rac_llm_stream_callback_t)(const char* token, bool is_complete, const rac_llm_result_t* result, void* context);

// Swift adapter bridges old-style to new-style
private func createStreamAdapter(
    continuation: AsyncThrowingStream<String, Error>.Continuation
) -> (UnsafeRawPointer, rac_llm_stream_callback_t) {
    let wrapper = StreamContinuationWrapper(continuation: continuation)
    let ptr = Unmanaged.passRetained(wrapper).toOpaque()

    let callback: rac_llm_stream_callback_t = { token, isComplete, result, context in
        guard let context = context else { return }
        let wrapper = Unmanaged<StreamContinuationWrapper>.fromOpaque(context)
        let cont = wrapper.takeUnretainedValue()

        if let token = token {
            cont.continuation.yield(String(cString: token))
        }

        if isComplete {
            cont.continuation.finish()
            wrapper.release()
        }
    }

    return (ptr, callback)
}
```

---

## Tasks Overview

| Task ID | Description | Effort | Dependencies |
|---------|-------------|--------|--------------|
| 3.1 | Update `Package.swift` with new binary targets | 2 days | Phase 2 |
| 3.2 | Create `CRACommons` Swift bridge module | 2 days | 3.1 |
| 3.3 | Implement Swift Platform Adapter | 3 days | 3.2 |
| 3.4 | Refactor `LlamaCPPRuntime` to use new XCFramework | 3 days | 3.2, 3.3 |
| 3.5 | Refactor `ONNXRuntime` to use new XCFramework | 3 days | 3.2, 3.3 |
| 3.6 | Update Registries for dual registration | 2 days | 3.4, 3.5 |
| 3.7 | Integration testing | 3 days | All above |

---

## Task 3.1: Update Package.swift

### Key Changes
- Replace single `RunAnywhereCoreBinary` with modular binaries
- Add C bridge modules for each backend
- Remove `-all_load` linker flag for size optimization

### New Package.swift

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription
import Foundation

let packageDir = URL(fileURLWithPath: #file).deletingLastPathComponent().path

// =============================================================================
// CONFIGURATION
// =============================================================================
let useLocalBinaries = false
let commonsVersion = "1.0.0"
let binaryBaseURL = "https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/v\(commonsVersion)"

let package = Package(
    name: "RunAnywhere",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        // =================================================================
        // Core SDK - Lightweight, no backends
        // =================================================================
        .library(
            name: "RunAnywhere",
            targets: ["RunAnywhere"]
        ),

        // =================================================================
        // LlamaCPP Backend - Adds LLM capability (~15MB)
        // =================================================================
        .library(
            name: "RunAnywhereLlamaCPP",
            targets: ["LlamaCPPRuntime"]
        ),

        // =================================================================
        // ONNX Backend - Adds STT/TTS/VAD capabilities (~50MB)
        // =================================================================
        .library(
            name: "RunAnywhereONNX",
            targets: ["ONNXRuntime"]
        ),

        // =================================================================
        // Apple AI Backend - Apple Intelligence (iOS 26+)
        // =================================================================
        .library(
            name: "RunAnywhereAppleAI",
            targets: ["FoundationModelsAdapter"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", from: "4.3.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.6.0"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
    ],
    targets: [
        // =================================================================
        // Core SDK - Depends only on RACommons
        // =================================================================
        .target(
            name: "RunAnywhere",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Files", package: "Files"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "DeviceKit", package: "DeviceKit"),
                .product(name: "SWCompression", package: "SWCompression"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                "CRACommons",
                "RACommonsBinary",
            ],
            path: "Sources/RunAnywhere",
            swiftSettings: [
                .define("SWIFT_PACKAGE"),
                .define("RAC_COMMONS_ENABLED")
            ]
        ),

        // =================================================================
        // C Bridge for Commons (rac_* headers)
        // =================================================================
        .target(
            name: "CRACommons",
            dependencies: ["RACommonsBinary"],
            path: "Sources/CRACommons",
            publicHeadersPath: "include"
        ),

        // =================================================================
        // LlamaCPP Backend Module
        // =================================================================
        .target(
            name: "LlamaCPPRuntime",
            dependencies: [
                "RunAnywhere",
                "CRABackendLlamaCPP",
                "RABackendLlamaCPPBinary",
            ],
            path: "Sources/LlamaCPPRuntime",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                // NO -all_load - use selective linking for size
                .unsafeFlags(["-ObjC"]),  // Only for ObjC categories
            ]
        ),

        .target(
            name: "CRABackendLlamaCPP",
            dependencies: ["RABackendLlamaCPPBinary", "CRACommons"],
            path: "Sources/CRABackendLlamaCPP",
            publicHeadersPath: "include"
        ),

        // =================================================================
        // ONNX Backend Module
        // =================================================================
        .target(
            name: "ONNXRuntime",
            dependencies: [
                "RunAnywhere",
                "CRABackendONNX",
                "RABackendONNXBinary",
            ],
            path: "Sources/ONNXRuntime",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedLibrary("archive"),
                .linkedLibrary("bz2"),
                .unsafeFlags(["-ObjC"]),
            ]
        ),

        .target(
            name: "CRABackendONNX",
            dependencies: ["RABackendONNXBinary", "CRACommons"],
            path: "Sources/CRABackendONNX",
            publicHeadersPath: "include"
        ),

        // =================================================================
        // Apple AI Backend (no native binary needed)
        // =================================================================
        .target(
            name: "FoundationModelsAdapter",
            dependencies: ["RunAnywhere"],
            path: "Sources/FoundationModelsAdapter"
        ),

    ] + binaryTargets()
)

// =============================================================================
// BINARY TARGET SELECTION
// =============================================================================
func binaryTargets() -> [Target] {
    if useLocalBinaries {
        return [
            .binaryTarget(
                name: "RACommonsBinary",
                path: "Binaries/RACommons.xcframework"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                path: "Binaries/RABackendLlamaCPP.xcframework"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                path: "Binaries/RABackendONNX.xcframework"
            ),
        ]
    } else {
        return [
            .binaryTarget(
                name: "RACommonsBinary",
                url: "\(binaryBaseURL)/RACommons.xcframework.zip",
                checksum: "CHECKSUM_PLACEHOLDER_COMMONS"
            ),
            .binaryTarget(
                name: "RABackendLlamaCPPBinary",
                url: "\(binaryBaseURL)/RABackendLlamaCPP.xcframework.zip",
                checksum: "CHECKSUM_PLACEHOLDER_LLAMACPP"
            ),
            .binaryTarget(
                name: "RABackendONNXBinary",
                url: "\(binaryBaseURL)/RABackendONNX.xcframework.zip",
                checksum: "CHECKSUM_PLACEHOLDER_ONNX"
            ),
        ]
    }
}
```

---

## Task 3.2: Create CRACommons Bridge Module

### Directory Structure

```
Sources/CRACommons/
├── include/
│   ├── CRACommons.h           # Umbrella header
│   ├── rac_core.h             # From runanywhere-commons
│   ├── rac_types.h
│   ├── rac_error.h
│   ├── rac_events.h
│   ├── rac_platform_adapter.h
│   └── module.modulemap
└── dummy.c
```

### Module Map

```
// Sources/CRACommons/include/module.modulemap
module CRACommons {
    umbrella header "CRACommons.h"
    export *
    module * { export * }

    link "c++"
}
```

### Umbrella Header

```c
// Sources/CRACommons/include/CRACommons.h
#ifndef CRACOMMONS_H
#define CRACOMMONS_H

#include "rac_core.h"
#include "rac_types.h"
#include "rac_error.h"
#include "rac_events.h"
#include "rac_platform_adapter.h"

#endif // CRACOMMONS_H
```

---

## Task 3.3: Implement Swift Platform Adapter

### SwiftPlatformAdapter.swift

```swift
// Sources/RunAnywhere/Foundation/Platform/SwiftPlatformAdapter.swift

import Foundation
import CRACommons

/// Implements the C platform adapter interface for iOS/macOS
final class SwiftPlatformAdapter: @unchecked Sendable {

    static let shared = SwiftPlatformAdapter()

    private var adapter: rac_platform_adapter_t

    private init() {
        adapter = rac_platform_adapter_t()
        setupCallbacks()
    }

    /// Get the C adapter struct to pass to rac_set_platform_adapter()
    func getAdapter() -> UnsafePointer<rac_platform_adapter_t> {
        return withUnsafePointer(to: &adapter) { $0 }
    }

    private func setupCallbacks() {
        adapter.context = Unmanaged.passUnretained(self).toOpaque()

        // =====================================================================
        // FILE SYSTEM
        // =====================================================================

        adapter.file_exists = { path, exists, ctx in
            guard let path = path.map({ String(cString: $0) }),
                  let exists = exists else {
                return RAC_ERROR_NULL_POINTER
            }
            exists.pointee = FileManager.default.fileExists(atPath: path)
            return RAC_SUCCESS
        }

        adapter.file_read = { path, data, len, ctx in
            guard let pathStr = path.map({ String(cString: $0) }),
                  let data = data,
                  let len = len else {
                return RAC_ERROR_NULL_POINTER
            }

            do {
                let fileData = try Data(contentsOf: URL(fileURLWithPath: pathStr))
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: fileData.count)
                fileData.copyBytes(to: buffer, count: fileData.count)
                data.pointee = buffer
                len.pointee = fileData.count
                return RAC_SUCCESS
            } catch {
                return RAC_ERROR_FILE_READ_FAILED
            }
        }

        adapter.file_write = { path, data, len, ctx in
            guard let pathStr = path.map({ String(cString: $0) }),
                  let data = data else {
                return RAC_ERROR_NULL_POINTER
            }

            do {
                let fileData = Data(bytes: data, count: len)
                try fileData.write(to: URL(fileURLWithPath: pathStr))
                return RAC_SUCCESS
            } catch {
                return RAC_ERROR_FILE_WRITE_FAILED
            }
        }

        adapter.file_delete = { path, ctx in
            guard let pathStr = path.map({ String(cString: $0) }) else {
                return RAC_ERROR_NULL_POINTER
            }

            do {
                try FileManager.default.removeItem(atPath: pathStr)
                return RAC_SUCCESS
            } catch {
                return RAC_ERROR_FILE_NOT_FOUND
            }
        }

        adapter.file_size = { path, size, ctx in
            guard let pathStr = path.map({ String(cString: $0) }),
                  let size = size else {
                return RAC_ERROR_NULL_POINTER
            }

            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: pathStr)
                size.pointee = (attrs[.size] as? Int) ?? 0
                return RAC_SUCCESS
            } catch {
                return RAC_ERROR_FILE_NOT_FOUND
            }
        }

        adapter.dir_create = { path, ctx in
            guard let pathStr = path.map({ String(cString: $0) }) else {
                return RAC_ERROR_NULL_POINTER
            }

            do {
                try FileManager.default.createDirectory(
                    atPath: pathStr,
                    withIntermediateDirectories: true
                )
                return RAC_SUCCESS
            } catch {
                return RAC_ERROR_FILE_WRITE_FAILED
            }
        }

        // =====================================================================
        // HTTP - NOT IMPLEMENTED (returns RAC_ERROR_NOT_SUPPORTED)
        // All networking handled by Swift SDK's DownloadService
        // =====================================================================

        adapter.http_request = { req, resp, ctx in
            rac_set_last_error_details("HTTP not supported via platform adapter. Use Swift SDK directly.")
            return RAC_ERROR_NOT_SUPPORTED
        }

        adapter.http_download = { url, destPath, progress, progressCtx, ctx in
            rac_set_last_error_details("Downloads not supported via platform adapter. Use Swift SDK directly.")
            return RAC_ERROR_NOT_SUPPORTED
        }

        // =====================================================================
        // SECURE STORAGE (Keychain)
        // =====================================================================

        adapter.secure_get = { key, value, len, ctx in
            guard let keyStr = key.map({ String(cString: $0) }),
                  let value = value,
                  let len = len else {
                return RAC_ERROR_NULL_POINTER
            }

            if let stored = KeychainManager.shared.get(key: keyStr) {
                let cString = stored.utf8CString
                let needed = cString.count

                if len.pointee < needed {
                    len.pointee = needed
                    return RAC_ERROR_BUFFER_TOO_SMALL
                }

                cString.withUnsafeBytes { bytes in
                    value.initialize(from: bytes.bindMemory(to: CChar.self).baseAddress!, count: needed)
                }
                len.pointee = needed
                return RAC_SUCCESS
            }

            return RAC_ERROR_FILE_NOT_FOUND
        }

        adapter.secure_set = { key, value, ctx in
            guard let keyStr = key.map({ String(cString: $0) }),
                  let valueStr = value.map({ String(cString: $0) }) else {
                return RAC_ERROR_NULL_POINTER
            }

            KeychainManager.shared.set(key: keyStr, value: valueStr)
            return RAC_SUCCESS
        }

        adapter.secure_delete = { key, ctx in
            guard let keyStr = key.map({ String(cString: $0) }) else {
                return RAC_ERROR_NULL_POINTER
            }

            KeychainManager.shared.delete(key: keyStr)
            return RAC_SUCCESS
        }

        // =====================================================================
        // LOGGING
        // =====================================================================

        adapter.log = { level, tag, message, ctx in
            guard let tagStr = tag.map({ String(cString: $0) }),
                  let msgStr = message.map({ String(cString: $0) }) else {
                return
            }

            let logLevel: LogLevel
            switch level {
            case RAC_LOG_DEBUG: logLevel = .debug
            case RAC_LOG_INFO: logLevel = .info
            case RAC_LOG_WARNING: logLevel = .warning
            case RAC_LOG_ERROR: logLevel = .error
            case RAC_LOG_FAULT: logLevel = .fault
            default: logLevel = .info
            }

            SDKLogger(category: tagStr).log(level: logLevel, msgStr)
        }

        // =====================================================================
        // CLOCK
        // =====================================================================

        adapter.now_ms = { ctx in
            return UInt64(Date().timeIntervalSince1970 * 1000)
        }

        // =====================================================================
        // MEMORY INFO
        // =====================================================================

        adapter.memory_info = { info, ctx in
            guard let info = info else {
                return RAC_ERROR_NULL_POINTER
            }

            var taskInfo = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

            let result = withUnsafeMutablePointer(to: &taskInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }

            if result == KERN_SUCCESS {
                info.pointee.used_bytes = taskInfo.resident_size
                info.pointee.total_bytes = ProcessInfo.processInfo.physicalMemory
                info.pointee.available_bytes = info.pointee.total_bytes - info.pointee.used_bytes
            }

            return RAC_SUCCESS
        }
    }

    /// Initialize commons with platform adapter
    func initializeCommons(environment: SDKEnvironment) throws {
        // Set platform adapter first
        let adapterResult = rac_set_platform_adapter(getAdapter())
        guard adapterResult == RAC_SUCCESS else {
            throw SDKError.initialization("Failed to set platform adapter: \(String(cString: rac_error_message(adapterResult)))")
        }

        // Initialize commons
        var config = rac_config_t()
        rac_config_init(&config)
        config.environment = environment.toCommonsEnvironment()
        config.enable_telemetry = true

        let initResult = rac_init(&config)
        guard initResult == RAC_SUCCESS else {
            throw SDKError.initialization("Failed to initialize commons: \(String(cString: rac_error_message(initResult)))")
        }
    }
}

// Extension to map Swift environment to commons environment
extension SDKEnvironment {
    func toCommonsEnvironment() -> rac_environment_t {
        switch self {
        case .development: return RAC_ENV_DEVELOPMENT
        case .staging: return RAC_ENV_STAGING
        case .production: return RAC_ENV_PRODUCTION
        }
    }
}
```

---

## Task 3.4: Refactor LlamaCPPRuntime

### LlamaCPPService.swift

```swift
// Sources/LlamaCPPRuntime/LlamaCPPService.swift

import Foundation
import RunAnywhere
import CRACommons
import CRABackendLlamaCPP

/// LLM service implementation using LlamaCpp backend
public final class LlamaCPPService: LLMService, @unchecked Sendable {

    private var handle: rac_llm_handle_t?
    private let queue = DispatchQueue(label: "ai.runanywhere.llamacpp", qos: .userInitiated)

    public init() {}

    public func initialize(modelPath: String, config: LLMConfiguration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                var llamaConfig = rac_llamacpp_config_t()
                rac_llamacpp_config_init(&llamaConfig)

                modelPath.withCString { pathPtr in
                    llamaConfig.model_path = pathPtr
                    llamaConfig.context_length = UInt32(config.contextLength ?? 2048)
                    llamaConfig.gpu_layers = UInt32(config.gpuLayers ?? 0)
                    llamaConfig.threads = UInt32(config.threads ?? 0)

                    var handle: rac_llm_handle_t?
                    let result = rac_llm_llamacpp_create(&handle, &llamaConfig)

                    if result == RAC_SUCCESS, let h = handle {
                        self.handle = h
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: SDKError.llm(
                            .modelLoadFailed,
                            String(cString: rac_error_message(result))
                        ))
                    }
                }
            }
        }
    }

    public func generate(prompt: String, options: LLMGenerationOptions) async throws -> LLMGenerationResult {
        guard let handle = handle else {
            throw SDKError.llm(.notInitialized, "LLM service not initialized")
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var opts = rac_llm_options_t()
                rac_llm_options_init(&opts)
                opts.max_tokens = UInt32(options.maxTokens ?? 256)
                opts.temperature = options.temperature ?? 0.7
                opts.top_p = options.topP ?? 0.9
                opts.top_k = UInt32(options.topK ?? 40)

                var result = rac_llm_result_t()

                prompt.withCString { promptPtr in
                    let status = rac_llm_llamacpp_generate(handle, promptPtr, &opts, &result)

                    if status == RAC_SUCCESS {
                        let text = result.text.map { String(cString: $0) } ?? ""

                        let genResult = LLMGenerationResult(
                            text: text,
                            promptTokens: Int(result.prompt_tokens),
                            completionTokens: Int(result.completion_tokens),
                            timeToFirstTokenMs: Double(result.time_to_first_token_ms),
                            totalTimeMs: Double(result.total_time_ms),
                            tokensPerSecond: Double(result.tokens_per_second)
                        )

                        // Free C-allocated result
                        rac_llm_result_free(&result)

                        continuation.resume(returning: genResult)
                    } else {
                        continuation.resume(throwing: SDKError.llm(
                            .generationFailed,
                            String(cString: rac_error_message(status))
                        ))
                    }
                }
            }
        }
    }

    public func generateStream(
        prompt: String,
        options: LLMGenerationOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let handle = self.handle else {
                continuation.finish(throwing: SDKError.llm(.notInitialized, "LLM service not initialized"))
                return
            }

            queue.async {
                var opts = rac_llm_options_t()
                rac_llm_options_init(&opts)
                opts.max_tokens = UInt32(options.maxTokens ?? 256)
                opts.temperature = options.temperature ?? 0.7
                opts.top_p = options.topP ?? 0.9

                // Create wrapper for continuation
                let wrapper = StreamContinuationWrapper(continuation: continuation)
                let contextPtr = Unmanaged.passRetained(wrapper).toOpaque()

                let callback: rac_llm_stream_callback_t = { token, isComplete, result, context in
                    guard let context = context else { return }
                    let wrapper = Unmanaged<StreamContinuationWrapper>.fromOpaque(context)
                    let cont = wrapper.takeUnretainedValue()

                    if let token = token {
                        cont.continuation.yield(String(cString: token))
                    }

                    if isComplete {
                        cont.continuation.finish()
                        wrapper.release()
                    }
                }

                prompt.withCString { promptPtr in
                    let status = rac_llm_llamacpp_generate_stream(
                        handle,
                        promptPtr,
                        &opts,
                        callback,
                        contextPtr
                    )

                    if status != RAC_SUCCESS {
                        continuation.finish(throwing: SDKError.llm(
                            .generationFailed,
                            String(cString: rac_error_message(status))
                        ))
                    }
                }
            }
        }
    }

    public func cancel() async throws {
        guard let handle = handle else { return }
        rac_llm_llamacpp_cancel(handle)
    }

    public func cleanup() async throws {
        guard let handle = handle else { return }
        rac_llm_llamacpp_destroy(handle)
        self.handle = nil
    }
}

// Helper class to bridge Swift async continuation to C callback
private final class StreamContinuationWrapper: @unchecked Sendable {
    let continuation: AsyncThrowingStream<String, Error>.Continuation

    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }
}
```

---

## Task 3.6: Update Registries for Dual Registration

### LlamaCPPRuntime.swift

```swift
// Sources/LlamaCPPRuntime/LlamaCPPRuntime.swift

import Foundation
import RunAnywhere
import CRACommons
import CRABackendLlamaCPP

/// LlamaCPP module providing LLM capability
public enum LlamaCPP: RunAnywhereModule {
    public static let moduleId = "llamacpp"
    public static let moduleName = "LlamaCPP"
    public static let capabilities: Set<CapabilityType> = [.llm]
    public static let inferenceFramework: InferenceFramework = .llamaCPP
    public static let defaultPriority: Int = 100

    public static var storageStrategy: ModelStorageStrategy? { nil }
    public static var downloadStrategy: DownloadStrategy? { nil }

    @MainActor
    public static func register(priority: Int = 100) {
        // 1. Register with C++ commons (backend-level)
        let result = rac_backend_llamacpp_register()
        if result != RAC_SUCCESS {
            SDKLogger(category: "LlamaCPP").error(
                "Failed to register C++ backend: \(String(cString: rac_error_message(result)))"
            )
        }

        // 2. Register Swift-side factory with ServiceRegistry
        ServiceRegistry.shared.registerLLM(
            name: moduleName,
            priority: priority,
            canHandle: { modelId in
                guard let modelId = modelId else { return true }
                return modelId.contains(".gguf") ||
                       modelId.contains("llamacpp") ||
                       modelId.contains("llama")
            },
            factory: { config in
                let service = LlamaCPPService()
                if let modelPath = config.modelPath {
                    try await service.initialize(modelPath: modelPath, config: config)
                }
                return service
            }
        )

        SDKLogger(category: "LlamaCPP").info("LlamaCPP backend registered (C++ + Swift)")
    }
}

// Auto-discovery support
extension LlamaCPP {
    private static let _autoRegister: Void = {
        ModuleDiscovery.register(LlamaCPP.self)
    }()

    public static func ensureRegistered() {
        _ = _autoRegister
    }
}
```

---

## Task 3.7: RunAnywhere.reset() for Testing

### Add to RunAnywhere Public API

```swift
// Sources/RunAnywhere/Public/RunAnywhere.swift

public extension RunAnywhere {
    /// Reset SDK state (for testing only)
    ///
    /// This resets:
    /// - Module registry
    /// - Service registry
    /// - Commons layer state
    ///
    /// - Warning: Only use in test environments
    @MainActor
    static func reset() {
        // Reset Swift registries
        ModuleRegistry.shared.reset()

        // Reset C++ commons (if initialized)
        if rac_is_initialized() {
            rac_shutdown()
        }

        SDKLogger(category: "RunAnywhere").info("SDK reset")
    }
}
```

---

## Error Code Mapping

The Swift SDK maps between commons error codes (`RAC_*`) and existing error patterns:

```swift
// Sources/RunAnywhere/Foundation/Errors/CommonsErrorMapping.swift

import CRACommons

extension rac_result_t {
    /// Map commons error to SDK error
    func toSDKError(context: String = "") -> SDKError? {
        switch self {
        case RAC_SUCCESS:
            return nil

        case RAC_ERROR_NOT_INITIALIZED:
            return SDKError.initialization("Commons not initialized: \(context)")

        case RAC_ERROR_MODEL_NOT_LOADED, RAC_ERROR_MODEL_LOAD_FAILED:
            return SDKError.llm(.modelLoadFailed, context)

        case RAC_ERROR_COMPONENT_FAILED:
            return SDKError.llm(.generationFailed, context)

        case RAC_ERROR_CANCELLED:
            return SDKError.llm(.cancelled, context)

        case RAC_ERROR_OUT_OF_MEMORY:
            return SDKError.resource(.insufficientMemory, context)

        case RAC_ERROR_BACKEND_NOT_FOUND:
            return SDKError.llm(.serviceNotAvailable, context)

        default:
            return SDKError.unknown(String(cString: rac_error_message(self)))
        }
    }
}
```

---

## Definition of Done

- [ ] `Package.swift` updated with modular binary targets
- [ ] `-all_load` removed, using `-ObjC` only
- [ ] `CRACommons` bridge module created and working
- [ ] `SwiftPlatformAdapter` implements file, secure storage, logging, clock, memory
- [ ] HTTP callbacks return `RAC_ERROR_NOT_SUPPORTED`
- [ ] `LlamaCPPRuntime` refactored to use new `rac_*` APIs
- [ ] `ONNXRuntime` refactored to use new XCFramework
- [ ] Dual registration: C++ backend + Swift service factory
- [ ] `RunAnywhere.reset()` added for testing
- [ ] Error code mapping implemented
- [ ] All existing tests pass
- [ ] New integration tests pass

---

*Phase 3 Duration: 3 weeks*
