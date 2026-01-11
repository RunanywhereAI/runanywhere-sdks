//
//  CppBridge+Services.swift
//  RunAnywhere SDK
//
//  Service registry bridge extension for C++ interop.
//

import CRACommons
import Foundation

// MARK: - Services Bridge (Service Registry Queries)

extension CppBridge {

    /// Bridge for querying the C++ service registry
    /// Provides runtime discovery of registered modules and service providers
    public enum Services {

        /// Registered provider info
        public struct ProviderInfo { // swiftlint:disable:this nesting
            public let name: String
            public let capability: SDKComponent
            public let priority: Int
        }

        /// Registered module info
        public struct ModuleInfo { // swiftlint:disable:this nesting
            public let id: String
            public let name: String
            public let version: String
            public let capabilities: Set<SDKComponent>
        }

        // MARK: - Provider Queries

        /// List all providers for a capability
        /// - Parameter capability: The capability to query (llm, stt, tts, vad)
        /// - Returns: Array of provider names sorted by priority (highest first)
        public static func listProviders(for capability: SDKComponent) -> [String] {
            let cCapability = capability.toC()

            var namesPtr: UnsafeMutablePointer<UnsafePointer<CChar>?>?
            var count: Int = 0

            let result = rac_service_list_providers(cCapability, &namesPtr, &count)
            guard result == RAC_SUCCESS, let names = namesPtr else {
                return []
            }

            var providers: [String] = []
            for i in 0..<count {
                if let name = names[i] {
                    providers.append(String(cString: name))
                }
            }

            return providers
        }

        /// Check if any provider is registered for a capability
        public static func hasProvider(for capability: SDKComponent) -> Bool {
            !listProviders(for: capability).isEmpty
        }

        /// Check if a specific provider is registered
        public static func isProviderRegistered(_ name: String, for capability: SDKComponent) -> Bool {
            listProviders(for: capability).contains(name)
        }

        // MARK: - Module Queries

        /// List all registered modules
        /// - Returns: Array of module info
        public static func listModules() -> [ModuleInfo] {
            var modulesPtr: UnsafePointer<rac_module_info_t>?
            var count: Int = 0

            let result = rac_module_list(&modulesPtr, &count)
            guard result == RAC_SUCCESS, let modules = modulesPtr else {
                return []
            }

            var moduleInfos: [ModuleInfo] = []
            for i in 0..<count {
                let module = modules[i]

                var capabilities: Set<SDKComponent> = []
                if let caps = module.capabilities {
                    for j in 0..<Int(module.num_capabilities) {
                        if let component = SDKComponent.from(caps[j]) {
                            capabilities.insert(component)
                        }
                    }
                }

                moduleInfos.append(ModuleInfo(
                    id: module.id.map { String(cString: $0) } ?? "",
                    name: module.name.map { String(cString: $0) } ?? "",
                    version: module.version.map { String(cString: $0) } ?? "",
                    capabilities: capabilities
                ))
            }

            return moduleInfos
        }

        /// Get info for a specific module
        public static func getModule(_ moduleId: String) -> ModuleInfo? {
            var modulePtr: UnsafePointer<rac_module_info_t>?

            let result = moduleId.withCString { idPtr in
                rac_module_get_info(idPtr, &modulePtr)
            }

            guard result == RAC_SUCCESS, let module = modulePtr?.pointee else {
                return nil
            }

            var capabilities: Set<SDKComponent> = []
            if let caps = module.capabilities {
                for j in 0..<Int(module.num_capabilities) {
                    if let component = SDKComponent.from(caps[j]) {
                        capabilities.insert(component)
                    }
                }
            }

            return ModuleInfo(
                id: module.id.map { String(cString: $0) } ?? "",
                name: module.name.map { String(cString: $0) } ?? "",
                version: module.version.map { String(cString: $0) } ?? "",
                capabilities: capabilities
            )
        }

        /// Check if a module is registered
        public static func isModuleRegistered(_ moduleId: String) -> Bool {
            getModule(moduleId) != nil
        }

        // MARK: - Platform Service Registration

        /// Context for platform service callbacks
        /// Internal for callback access (C callbacks are outside the extension)
        class PlatformServiceContext { // swiftlint:disable:this nesting
            let canHandle: (String?) -> Bool

            init(canHandle: @escaping (String?) -> Bool) {
                self.canHandle = canHandle
            }
        }

        // Internal for callback access (C callbacks are outside the extension)
        static var platformContexts: [String: PlatformServiceContext] = [:]
        static let platformLock = NSLock()

        /// Register a platform-only service with the C++ registry
        ///
        /// This allows Swift-only services (like SystemTTS, AppleAI) to be registered
        /// with the C++ service registry, making them discoverable alongside C++ backends.
        ///
        /// - Parameters:
        ///   - name: Provider name (e.g., "SystemTTS")
        ///   - capability: Capability this provider offers
        ///   - priority: Priority (higher = preferred)
        ///   - canHandle: Closure to check if provider can handle a request
        ///   - create: Factory closure to create the service (reserved for future use)
        /// - Returns: true if registration succeeded
        @discardableResult
        public static func registerPlatformService(
            name: String,
            capability: SDKComponent,
            priority: Int,
            canHandle: @escaping (String?) -> Bool,
            create _: @escaping () async throws -> Any
        ) -> Bool {
            platformLock.lock()
            defer { platformLock.unlock() }

            // Store context for callbacks
            let context = PlatformServiceContext(canHandle: canHandle)
            platformContexts[name] = context

            // Create C provider struct
            var provider = rac_service_provider_t()
            provider.capability = capability.toC()
            provider.priority = Int32(priority)

            // Use global callbacks that look up the context by name
            // Note: We store the name as user_data
            let namePtr = strdup(name)
            provider.user_data = UnsafeMutableRawPointer(namePtr)
            provider.can_handle = platformCanHandleCallback
            provider.create = platformCreateCallback

            let result = name.withCString { namePtr in
                provider.name = namePtr
                return rac_service_register_provider(&provider)
            }

            if result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED {
                // Cleanup on failure
                platformContexts.removeValue(forKey: name)
                if let namePtr = provider.user_data?.assumingMemoryBound(to: CChar.self) {
                    free(namePtr)
                }
                return false
            }

            return true
        }

        /// Unregister a platform service
        public static func unregisterPlatformService(name: String, capability: SDKComponent) {
            platformLock.lock()
            defer { platformLock.unlock() }

            platformContexts.removeValue(forKey: name)

            _ = name.withCString { namePtr in
                rac_service_unregister_provider(namePtr, capability.toC())
            }
        }
    }
}

// MARK: - Platform Service Callbacks

/// Callback for checking if platform service can handle request
private func platformCanHandleCallback(
    request: UnsafePointer<rac_service_request_t>?,
    userData: UnsafeMutableRawPointer?
) -> rac_bool_t {
    guard let userData = userData else { return RAC_FALSE }

    let name = String(cString: userData.assumingMemoryBound(to: CChar.self))

    CppBridge.Services.platformLock.lock()
    guard let context = CppBridge.Services.platformContexts[name] else {
        CppBridge.Services.platformLock.unlock()
        return RAC_FALSE
    }
    CppBridge.Services.platformLock.unlock()

    let identifier = request?.pointee.identifier.map { String(cString: $0) }
    return context.canHandle(identifier) ? RAC_TRUE : RAC_FALSE
}

/// Callback for creating platform service
private func platformCreateCallback(
    request _: UnsafePointer<rac_service_request_t>?,
    userData: UnsafeMutableRawPointer?
) -> rac_handle_t? {
    guard let userData = userData else { return nil }

    let name = String(cString: userData.assumingMemoryBound(to: CChar.self))

    CppBridge.Services.platformLock.lock()
    guard CppBridge.Services.platformContexts[name] != nil else {
        CppBridge.Services.platformLock.unlock()
        return nil
    }
    CppBridge.Services.platformLock.unlock()

    // Platform services are Swift objects - we return a dummy handle
    // The actual service is stored in the context and managed by Swift
    // This is a bridge pattern - C++ tracks that a service exists,
    // but Swift manages the actual instance
    return UnsafeMutableRawPointer(bitPattern: 0xDEADBEEF)  // Marker handle
}

// MARK: - SDKComponent C++ Conversion

extension SDKComponent {

    /// Convert to C++ capability type
    func toC() -> rac_capability_t {
        switch self {
        case .llm:
            return RAC_CAPABILITY_TEXT_GENERATION
        case .stt:
            return RAC_CAPABILITY_STT
        case .tts:
            return RAC_CAPABILITY_TTS
        case .vad:
            return RAC_CAPABILITY_VAD
        case .voice:
            // Voice agent uses multiple capabilities, default to text generation
            return RAC_CAPABILITY_TEXT_GENERATION
        case .embedding:
            // Embeddings use text generation capability
            return RAC_CAPABILITY_TEXT_GENERATION
        }
    }

    /// Convert from C++ capability type
    static func from(_ capability: rac_capability_t) -> SDKComponent? {
        switch capability {
        case RAC_CAPABILITY_TEXT_GENERATION:
            return .llm
        case RAC_CAPABILITY_STT:
            return .stt
        case RAC_CAPABILITY_TTS:
            return .tts
        case RAC_CAPABILITY_VAD:
            return .vad
        default:
            return nil
        }
    }
}
