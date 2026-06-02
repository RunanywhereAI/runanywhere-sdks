//
//  Cloud.swift
//  RunAnywhere
//
//  Generic cloud backend registration + credential/model registry.
//
//  `Cloud.register()` folds the cloud engine plugin into the commons
//  plugin registry by calling `rac_backend_cloud_register()` — the exact
//  mirror of `ONNX.register()` / `LlamaCPP.register()`. Once registered, the
//  unified "cloud" plugin serves RAC_PRIMITIVE_TRANSCRIBE and is routable
//  via `rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, …, hint="cloud")`, which
//  is how the hybrid router creates the online STT service. The concrete HTTP
//  provider (Sarvam first) is selected per model via the create config's
//  `"provider"` field, not by a distinct plugin.
//
//  The credential/model registry mirrors the Kotlin cloud-STT table: the app
//  pre-registers a provider + model string + API key under an id at startup,
//  and the router refers to it by id (the id is the HybridModel.id for the
//  online side). Registration is process-lifetime + thread-safe.
//

import CRACommons
import Foundation
import os

/// Generic cloud speech-to-text backend. Fronts one or more HTTP STT providers
/// (Sarvam first); the provider is data carried in each registered model entry.
public enum Cloud {

    private static let logger = SDKLogger(category: "Cloud")

    /// Default cloud STT provider when a caller omits one.
    public static let defaultProvider = "sarvam"

    /// cloud engine module version (binding side).
    public static let version = "2.0.0"

    // MARK: - Registration

    /// Guards the one-time plugin registration. Per AGENTS.md NSLock is
    /// forbidden — `OSAllocatedUnfairLock` only.
    private static let registrationState =
        OSAllocatedUnfairLock<Bool>(initialState: false)

    /// Register the cloud backend with the commons plugin registry.
    ///
    /// Calls `rac_backend_cloud_register()` so the unified "cloud"
    /// plugin (RAC_PRIMITIVE_TRANSCRIBE) becomes routable. Safe to call multiple
    /// times — subsequent calls are no-ops, and the C side treats
    /// `RAC_ERROR_MODULE_ALREADY_REGISTERED` as success.
    ///
    /// Linkage caveat (see rac_plugin_entry_cloud.h): the cloud engine
    /// registers via the explicit-register + static-shim pattern and is folded
    /// into the iOS commons static-plugin archive alongside sherpa/onnx/llamacpp,
    /// so `rac_backend_cloud_register` resolves from the shipped Apple
    /// binaries. The registration result is logged rather than thrown so a host
    /// without the engine still boots.
    public static func register() {
        let alreadyRegistered = registrationState.withLock { state -> Bool in
            if state { return true }
            state = true
            return false
        }
        guard !alreadyRegistered else {
            logger.debug("Cloud already registered, returning")
            return
        }

        logger.info("Registering cloud backend with commons registry...")
        let result = rac_backend_cloud_register()

        if result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED {
            // Roll back the flag so a later retry (e.g. after the engine is
            // linked in) can re-attempt registration.
            registrationState.withLock { $0 = false }
            let message = String(cString: rac_error_message(result))
            logger.error("Cloud registration failed: \(message)")
            return
        }

        logger.info("cloud backend registered (cloud STT, default provider \(defaultProvider))")
    }

    /// Unregister the cloud backend from the commons registry.
    public static func unregister() {
        let wasRegistered = registrationState.withLock { state -> Bool in
            let old = state
            state = false
            return old
        }
        guard wasRegistered else { return }
        _ = rac_backend_cloud_unregister()
        logger.info("cloud backend unregistered")
    }

    // MARK: - Credential / model registry

    /// A registered cloud-STT model: the provider, the wire model string + the
    /// credentials the engine needs, keyed by an app-chosen id.
    public struct ModelEntry: Sendable {
        public let id: String
        public let provider: String
        public let model: String
        public let apiKey: String
        public let languageCode: String?
        public let baseURL: String?
        public let timeoutMs: Int?
    }

    /// name → entry. Guarded by `OSAllocatedUnfairLock` (NSLock is forbidden).
    private static let registry =
        OSAllocatedUnfairLock<[String: ModelEntry]>(initialState: [:])

    /// Register a cloud-STT model under `id` so the router can refer to it by id
    /// from `HybridModel.onlineCloud(id)`.
    ///
    /// - Parameters:
    ///   - id:           App-chosen registry id (becomes the online HybridModel.id).
    ///   - provider:     Concrete cloud STT provider ("sarvam" by default). Carried
    ///                   into the config JSON as `"provider"` so the cloud
    ///                   engine selects the right HTTP backend.
    ///   - model:        Provider model id (e.g. "saarika:v2.5" for Sarvam).
    ///   - apiKey:       Provider API subscription key. Sensitive; never logged.
    ///   - languageCode: Optional BCP-47 hint ("en-IN"…). `nil` = auto-detect
    ///                   (the engine omits the language_code field).
    ///   - baseURL:      Optional endpoint override.
    ///   - timeoutMs:    Optional request timeout (milliseconds).
    public static func register(
        id: String,
        provider: String = defaultProvider,
        model: String,
        apiKey: String,
        languageCode: String? = nil,
        baseURL: String? = nil,
        timeoutMs: Int? = nil
    ) {
        precondition(!id.isEmpty, "Cloud registry id must be non-empty")
        precondition(!provider.isEmpty, "Cloud provider must be non-empty")
        precondition(!model.isEmpty, "Cloud model string must be non-empty")
        precondition(!apiKey.isEmpty, "Cloud apiKey must be non-empty")
        let entry = ModelEntry(
            id: id,
            provider: provider,
            model: model,
            apiKey: apiKey,
            languageCode: languageCode,
            baseURL: baseURL,
            timeoutMs: timeoutMs
        )
        registry.withLock { $0[id] = entry }
    }

    /// Look up a previously registered model by id.
    public static func lookup(_ id: String) -> ModelEntry? {
        registry.withLock { $0[id] }
    }

    /// True iff a model is registered under `id`.
    public static func isRegistered(_ id: String) -> Bool {
        registry.withLock { $0[id] != nil }
    }

    @discardableResult
    public static func unregisterModel(_ id: String) -> Bool {
        registry.withLock { $0.removeValue(forKey: id) != nil }
    }

    public static func clear() {
        registry.withLock { $0.removeAll() }
    }

    // MARK: - Config JSON

    /// Build the config JSON the routed "cloud" plugin's `create` expects
    /// from a registered entry. Carries `provider` so the engine selects the
    /// right HTTP backend. Internal — the router uses this to create the online
    /// service.
    static func configJSON(for id: String) throws -> String {
        guard let entry = lookup(id) else {
            throw SDKException(
                code: .invalidArgument,
                message: "Cloud model id '\(id)' not registered. "
                    + "Call Cloud.register(id:provider:model:apiKey:) at app startup.",
                category: .configuration
            )
        }
        var json: [String: Any] = [
            "provider": entry.provider,
            "api_key": entry.apiKey,
            "model": entry.model,
        ]
        if let languageCode = entry.languageCode { json["language_code"] = languageCode }
        if let baseURL = entry.baseURL { json["base_url"] = baseURL }
        if let timeoutMs = entry.timeoutMs { json["timeout_ms"] = timeoutMs }

        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
