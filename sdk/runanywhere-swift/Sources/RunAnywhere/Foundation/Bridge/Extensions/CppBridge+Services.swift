//
//  CppBridge+Services.swift
//  RunAnywhere SDK
//
//  Service registry bridge extension for C++ interop.
//
//  v3 Phase B10: migrated from legacy rac_service_* to the unified
//  rac_plugin_* registry. Platform service registration was removed
//  entirely — Apple platform services are now registered via the
//  C++ side (rac_plugin_entry_platform.cpp), which internally
//  invokes Swift callbacks via rac_platform_{llm,tts,diffusion}_
//  get_callbacks. The previous Swift-side `registerPlatformService`
//  path built a rac_service_provider_t with can_handle/create
//  callbacks; that whole shape is gone in v3.
//

import CRACommons
import Foundation

// MARK: - Services Bridge (Plugin Registry Queries)

extension CppBridge {

    /// Bridge for querying the C++ plugin registry.
    public enum Services {

        /// Registered plugin info (name + metadata priority).
        public struct ProviderInfo { // swiftlint:disable:this nesting
            public let name: String
            public let displayName: String?
            public let priority: Int
        }

        /// Registered module info.
        public struct ModuleInfo { // swiftlint:disable:this nesting
            public let id: String
            public let name: String
            public let version: String
            public let capabilities: Set<SDKComponent>
        }

        // MARK: - Plugin Queries

        /// List all plugin names registered for a capability, sorted by priority.
        public static func listProviders(for capability: SDKComponent) -> [String] {
            guard let primitive = capability.toPrimitive() else { return [] }

            // Fixed-size buffer — 16 plugins per primitive is well above the
            // current maximum (3 STT plugins, 2 TTS, 1 LLM, etc.). Bump if
            // needed.
            var slots: [UnsafePointer<rac_engine_vtable_t>?] = Array(repeating: nil, count: 16)
            var count: Int = 0
            let result = slots.withUnsafeMutableBufferPointer { buf -> rac_result_t in
                guard let base = buf.baseAddress else { return RAC_ERROR_NULL_POINTER }
                return rac_plugin_list(primitive, base, 16, &count)
            }
            guard result == RAC_SUCCESS else { return [] }

            var names: [String] = []
            names.reserveCapacity(count)
            for i in 0..<min(count, 16) {
                if let vt = slots[i], let cName = vt.pointee.metadata.name {
                    names.append(String(cString: cName))
                }
            }
            return names
        }

        /// Check if any plugin is registered for a capability.
        public static func hasProvider(for capability: SDKComponent) -> Bool {
            !listProviders(for: capability).isEmpty
        }

        /// Check if a specific plugin (by metadata.name, e.g. "llamacpp") is registered.
        public static func isProviderRegistered(_ name: String, for capability: SDKComponent) -> Bool {
            listProviders(for: capability).contains(name)
        }

        // MARK: - Module Queries (unchanged — module registry is independent)

        /// List all registered modules.
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

        /// Get info for a specific module.
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

        /// Check if a module is registered.
        public static func isModuleRegistered(_ moduleId: String) -> Bool {
            getModule(moduleId) != nil
        }
    }
}

// MARK: - SDKComponent ↔ rac_primitive_t / rac_capability_t conversion

extension SDKComponent {

    /// Convert to the GAP 02 `rac_primitive_t` enum used by the plugin registry.
    /// Returns nil for aggregate components (.voice, .rag) that span multiple
    /// primitives; callers should pick a specific primitive or iterate.
    func toPrimitive() -> rac_primitive_t? {
        switch self {
        case .llm:       return RAC_PRIMITIVE_GENERATE_TEXT
        case .vlm:       return RAC_PRIMITIVE_VLM
        case .stt:       return RAC_PRIMITIVE_TRANSCRIBE
        case .tts:       return RAC_PRIMITIVE_SYNTHESIZE
        case .vad:       return RAC_PRIMITIVE_DETECT_VOICE
        case .embeddings: return RAC_PRIMITIVE_EMBED
        case .diffusion: return RAC_PRIMITIVE_DIFFUSION
        case .voiceAgent, .rag, .wakeword, .speakerDiarization, .unspecified, .UNRECOGNIZED:
            return nil
        }
    }

    /// Convert to C++ capability type (still used by module registry queries).
    func toC() -> rac_capability_t {
        switch self {
        case .llm:       return RAC_CAPABILITY_TEXT_GENERATION
        case .vlm:       return RAC_CAPABILITY_VISION_LANGUAGE
        case .stt:       return RAC_CAPABILITY_STT
        case .tts:       return RAC_CAPABILITY_TTS
        case .vad:       return RAC_CAPABILITY_VAD
        case .voiceAgent:     return RAC_CAPABILITY_TEXT_GENERATION
        case .embeddings: return RAC_CAPABILITY_TEXT_GENERATION
        case .diffusion: return RAC_CAPABILITY_DIFFUSION
        case .rag:       return RAC_CAPABILITY_TEXT_GENERATION
        case .wakeword, .speakerDiarization, .unspecified, .UNRECOGNIZED:
            return RAC_CAPABILITY_TEXT_GENERATION
        }
    }

    /// Convert from C++ capability type.
    static func from(_ capability: rac_capability_t) -> SDKComponent? {
        switch capability {
        case RAC_CAPABILITY_TEXT_GENERATION: return .llm
        case RAC_CAPABILITY_VISION_LANGUAGE: return .vlm
        case RAC_CAPABILITY_STT:             return .stt
        case RAC_CAPABILITY_TTS:             return .tts
        case RAC_CAPABILITY_VAD:             return .vad
        case RAC_CAPABILITY_DIFFUSION:       return .diffusion
        default:                             return nil
        }
    }
}
