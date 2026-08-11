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
    /// credentials the engine needs, keyed by an app-chosen id. Backed by the
    /// generated `RACloudSttBackendConfig` (provider / model / apiKey /
    /// languageCode / baseURL / timeoutMs). Unset optionals map to the proto's
    /// empty-string / zero defaults.
    public typealias ModelEntry = RACloudSttBackendConfig

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
        var entry = ModelEntry()
        entry.provider = provider
        entry.model = model
        entry.apiKey = apiKey
        if let languageCode { entry.languageCode = languageCode }
        if let baseURL { entry.baseURL = baseURL }
        if let timeoutMs { entry.timeoutMs = Int32(timeoutMs) }
        let registeredEntry = entry
        registry.withLock { $0[id] = registeredEntry }
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
        var payload = CloudConfigPayload(provider: entry.provider, apiKey: entry.apiKey, model: entry.model)
        if !entry.languageCode.isEmpty { payload.languageCode = entry.languageCode }
        if !entry.baseURL.isEmpty { payload.baseURL = entry.baseURL }
        if entry.timeoutMs != 0 { payload.timeoutMs = Int(entry.timeoutMs) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw SDKException(
                code: .processingFailed,
                message: "Cloud config JSON for '\(id)' is not valid UTF-8",
                category: .configuration
            )
        }
        return json
    }
}

/// Wire shape of the config blob the routed "cloud" plugin's `create`
/// expects. snake_case keys: the cloud_stt engine reads snake_case out of
/// the config_json blob, so the keys are pinned explicitly — NOT derived
/// via a camelCase key-encoding strategy. Optional fields are omitted when
/// unset, matching the engine's defaults.
private struct CloudConfigPayload: Encodable {
    let provider: String
    let apiKey: String
    let model: String
    var languageCode: String?
    var baseURL: String?
    var timeoutMs: Int?

    enum CodingKeys: String, CodingKey {
        case provider
        case apiKey = "api_key"
        case model
        case languageCode = "language_code"
        case baseURL = "base_url"
        case timeoutMs = "timeout_ms"
    }
}
