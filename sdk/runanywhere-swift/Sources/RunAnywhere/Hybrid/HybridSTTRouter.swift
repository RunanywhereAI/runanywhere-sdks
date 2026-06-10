//
//  HybridSTTRouter.swift
//  RunAnywhere
//
//  THIN Swift binding over the commons STT hybrid router (rac_stt_hybrid_router
//  + its proto-byte ABI). Per-request dispatch between an on-device (offline,
//  sherpa) STT service and a cloud (online, cloud) STT service.
//
//  Division of labour — commons owns ALL routing:
//    * filter phase, rank/sort, confidence cascade, and primary→secondary
//      fallback all live in rac_stt_hybrid_router.cpp. NONE of that logic is
//      reimplemented here.
//  This binding only:
//    1. creates the router handle,
//    2. creates the two STT services through the registry-routed creation path
//       (rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, hint) → vt->stt_ops->create)
//       and attaches them with their descriptors,
//    3. registers any custom-filter predicates and installs the policy bytes,
//    4. drives the router's transcribe (normalising raw PCM16 input to a WAV
//       container so one payload serves both services) and decodes the
//       response.
//
//  Mirrors the Kotlin RACRouter feature surface: both SDKs register the
//  custom-filter predicate with commons (`rac_hybrid_register_custom_filter`)
//  and let the router own the entire filter phase.
//
//  Lifetime: the router does NOT own the underlying services. This actor keeps
//  each `rac_stt_service_t` in stable heap storage for the router's lifetime,
//  clears the router slots before destroying the services (avoiding the
//  use-after-free called out in rac_stt_hybrid_router.h), and tears everything
//  down in `close()`.
//

import CRACommons
import Foundation
import os
import SwiftProtobuf

/// A hybrid STT router pairing one offline + one online speech service.
///
/// Usage:
/// ```swift
/// Cloud.register()                  // fold the cloud plugin in
/// Cloud.register(id: "saaras", provider: "sarvam", model: "saaras:v2.5", apiKey: "…")
/// HybridDeviceState.setProvider(myProvider)   // optional: live NETWORK/Battery
///
/// let router = try HybridSTTRouter()
/// try router.setPair(
///     offline: .offlineSherpa("sherpa-onnx-whisper-tiny.en"),
///     online:  .onlineCloud("saaras"),
///     policy:  .init(hardFilters: [.network], cascade: .confidence(threshold: 0.5),
///                    rank: .preferLocalFirst)
/// )
/// var options = HybridTranscribeOptions()
/// options.sampleRate = 16_000
/// let result = try router.transcribe(pcm16Audio, options: options)
/// router.close()
/// ```
///
/// `@unchecked Sendable`: all mutable native state is funnelled through the
/// `OSAllocatedUnfairLock` (per AGENTS.md NSLock is forbidden); the C ABI
/// itself is thread-safe for transcribe + the slot setters.
public final class HybridSTTRouter: @unchecked Sendable {

    private static let logger = SDKLogger(category: "Hybrid.STTRouter")

    /// One attached STT service: the heap-stable `rac_stt_service_t` the router
    /// holds a pointer to, the engine ops that created it (to call `destroy`),
    /// and the strdup'd model id the struct's `model_id` field points at.
    ///
    /// `@unchecked Sendable`: the raw pointers are only ever touched while the
    /// `state` lock is held (the same justification the SDK's HandleStreamAdapter
    /// uses for its lock-guarded `UnsafeMutableRawPointer` state).
    private struct AttachedService: @unchecked Sendable {
        let servicePtr: UnsafeMutablePointer<rac_stt_service_t>
        let ops: UnsafePointer<rac_stt_service_ops_t>
        let modelIdCStr: UnsafeMutablePointer<CChar>
    }

    /// `@unchecked Sendable`: every field is mutated only under the `state`
    /// lock; the native handle + service pointers never escape it unguarded.
    private struct State: @unchecked Sendable {
        var handle: rac_handle_t?
        var offline: AttachedService?
        var online: AttachedService?
        /// Names of custom-filter predicates registered for the current policy,
        /// so `close()` can unregister exactly those.
        var customFilterNames: [String] = []
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    /// Create the native router handle.
    public init() throws {
        var handle: rac_handle_t?
        let rc = rac_stt_hybrid_router_create(&handle)
        guard rc == RAC_SUCCESS, let handle else {
            throw SDKException(
                code: .serviceNotAvailable,
                message: "rac_stt_hybrid_router_create failed (rc=\(rc))",
                category: .component
            )
        }
        state.withLock { $0.handle = handle }
    }

    // MARK: - Pair + policy

    /// Bind the offline + online models, install the policy, and register any
    /// custom-filter predicates. Replaces any previous pairing.
    public func setPair(
        offline: HybridModel,
        online: HybridModel,
        policy: HybridRoutingPolicy
    ) throws {
        guard let handle = state.withLock({ $0.handle }) else {
            throw notOpen()
        }

        // Build both services up-front so a failure on the online side doesn't
        // leave a half-attached router.
        let offlineService = try createService(for: offline)
        let onlineService: AttachedService
        do {
            onlineService = try createService(for: online)
        } catch {
            destroy(offlineService)
            throw error
        }

        // Serialize all proto bytes (descriptors + policy) up-front via the
        // generated SwiftProtobuf messages, before mutating any installed state.
        // A serialization failure only destroys the freshly created services and
        // leaves the previously installed pair / filters untouched. The router
        // copies the bytes into its own storage, so each array only needs to
        // outlive the corresponding call.
        let offlineDescriptor: [UInt8]
        let onlineDescriptor: [UInt8]
        let policyBytes: [UInt8]
        do {
            offlineDescriptor = try offline.descriptorBytes()
            onlineDescriptor = try online.descriptorBytes()
            policyBytes = try policy.serializedBytes()
        } catch {
            destroy(offlineService); destroy(onlineService)
            throw error
        }

        // Detach + destroy any previously attached services before swapping in
        // the new pair (clear router slots first — see header UAF note), and
        // retire the previous policy's custom-filter predicates so re-pairing
        // with a different policy doesn't leave stale named filters registered
        // in commons.
        clearAndDestroyServices(handle: handle)
        let previousFilterNames: [String] = state.withLock { current in
            let old = current.customFilterNames
            current.customFilterNames = []
            return old
        }
        for name in previousFilterNames { HybridCustomFilter.unregister(name: name) }

        let rcOff = rac_stt_hybrid_router_set_offline_service_proto(
            handle, offlineService.servicePtr,
            offlineDescriptor, offlineDescriptor.count
        )
        guard rcOff == RAC_SUCCESS else {
            destroy(offlineService); destroy(onlineService)
            throw SDKException(
                code: .serviceNotAvailable,
                message: "set_offline_service_proto failed (rc=\(rcOff))",
                category: .component
            )
        }
        let rcOn = rac_stt_hybrid_router_set_online_service_proto(
            handle, onlineService.servicePtr,
            onlineDescriptor, onlineDescriptor.count
        )
        guard rcOn == RAC_SUCCESS else {
            _ = rac_stt_hybrid_router_set_offline_service_proto(handle, nil, nil, 0)
            destroy(offlineService); destroy(onlineService)
            throw SDKException(
                code: .serviceNotAvailable,
                message: "set_online_service_proto failed (rc=\(rcOn))",
                category: .component
            )
        }

        // Register custom-filter predicates with commons BEFORE installing the
        // policy bytes, so the router can resolve each HybridFilter.custom name
        // the first time it filters. The router owns the eval — Swift only
        // supplies the named predicate.
        let customNames = policy.customFilters.map(\.name)
        for filter in policy.customFilters {
            HybridCustomFilter.register(name: filter.name, check: filter.check)
        }

        let rcPolicy = rac_stt_hybrid_router_set_policy_proto(
            handle, policyBytes, policyBytes.count
        )
        guard rcPolicy == RAC_SUCCESS else {
            for name in customNames { HybridCustomFilter.unregister(name: name) }
            _ = rac_stt_hybrid_router_set_offline_service_proto(handle, nil, nil, 0)
            _ = rac_stt_hybrid_router_set_online_service_proto(handle, nil, nil, 0)
            destroy(offlineService); destroy(onlineService)
            throw SDKException(
                code: .serviceNotAvailable,
                message: "set_policy_proto failed (rc=\(rcPolicy))",
                category: .component
            )
        }

        state.withLock { current in
            current.offline = offlineService
            current.online = onlineService
            current.customFilterNames = customNames
        }
    }

    // MARK: - Transcribe

    /// Run one transcribe request through the router. The router applies the
    /// installed policy (filters → rank → invoke → fallback) in commons and
    /// returns the chosen backend's result plus the routing decision.
    ///
    /// - Parameters:
    ///   - audio: Raw 16-bit mono PCM bytes (pass the capture rate via
    ///     `HybridTranscribeOptions.sampleRate`) OR file-encoded audio
    ///     (wav/mp3/flac/...). Raw PCM16 is wrapped in a WAV container here —
    ///     see `normalizeAudioPayload`; WAV input (RIFF/WAVE magic) and
    ///     declared compressed formats pass through unchanged.
    ///   - options: Optional language / sample-rate / audio-format hints
    ///     (proto-typed `HybridTranscribeOptions`).
    public func transcribe(
        _ audio: Data,
        options: HybridTranscribeOptions = .init()
    ) throws -> HybridTranscribeResult {
        guard let handle = state.withLock({ $0.handle }) else {
            throw notOpen()
        }

        let (payload, payloadOptions) = Self.normalizeAudioPayload(audio: audio, options: options)
        let requestBytes = try encodeRequest(audio: payload, options: payloadOptions)

        var outBytes: UnsafeMutablePointer<UInt8>?
        var outSize: Int = 0
        let rc = requestBytes.withUnsafeBufferPointer { buffer in
            rac_stt_hybrid_router_transcribe_proto(
                handle, buffer.baseAddress, buffer.count, &outBytes, &outSize
            )
        }

        defer {
            if let outBytes { rac_stt_hybrid_router_proto_buffer_free(outBytes) }
        }

        guard rc == RAC_SUCCESS, let outBytes, outSize > 0 else {
            throw SDKException(
                code: .serviceNotAvailable,
                message: "rac_stt_hybrid_router_transcribe_proto failed (rc=\(rc))",
                category: .component
            )
        }

        let responseData = Data(bytes: outBytes, count: outSize)
        return try decodeResponse(responseData)
    }

    // MARK: - Audio payload normalisation

    /// Sherpa's raw-PCM fallback rate, used when the caller gave none.
    private static let defaultSampleRate: Int32 = 16000

    /// Normalise the audio payload for the shared offline+online dispatch.
    /// Commons hands ONE payload to both services, and only a WAV container
    /// satisfies both: sherpa parses WAV inline (and falls back to raw
    /// PCM16), but cloud providers upload the bytes verbatim as an
    /// `audio/wav` file part and reject headerless PCM. Raw PCM16 is
    /// therefore wrapped via `RunAnywhere.pcm16ToWav` using the options'
    /// sample rate (16 kHz when unset, sherpa's own default). Input that is
    /// already a container — WAV by RIFF/WAVE magic, or a declared
    /// compressed format — passes through unchanged. Mirrors Kotlin's
    /// `normalizeAudioPayload`.
    private static func normalizeAudioPayload(
        audio: Data,
        options: HybridTranscribeOptions
    ) -> (payload: Data, options: HybridTranscribeOptions) {
        let isCompressed = options.audioFormat > CloudAudioFormat.wav.nativeValue
        if audio.isEmpty || isCompressed || isWavContainer(audio) {
            return (audio, options)
        }
        let sampleRate = options.sampleRate > 0 ? options.sampleRate : defaultSampleRate
        var normalized = options
        normalized.sampleRate = sampleRate
        normalized.audioFormat = CloudAudioFormat.wav.nativeValue
        return (RunAnywhere.pcm16ToWav(audio, sampleRate: Int(sampleRate)), normalized)
    }

    private static func isWavContainer(_ audio: Data) -> Bool {
        guard audio.count >= 12 else { return false }
        return audio.prefix(4).elementsEqual("RIFF".utf8)
            && audio.dropFirst(8).prefix(4).elementsEqual("WAVE".utf8)
    }

    // MARK: - Request encode / response decode

    /// Build a `runanywhere.v1.HybridSttTranscribeRequest` carrying the audio
    /// bytes, an (empty, present) routing context, and the options, via the
    /// generated SwiftProtobuf message.
    ///
    /// HybridRoutingContext currently has no fields — device-state lives behind
    /// the `rac_hybrid_device_state` vtable. The empty message is still set
    /// explicitly so the wire shape (field 2 present) is stable for future
    /// per-call hints, matching the C++/JNI peers.
    private func encodeRequest(audio: Data, options: HybridTranscribeOptions) throws -> [UInt8] {
        var request = RAHybridSttTranscribeRequest()
        request.audioBytes = audio
        request.context = RAHybridRoutingContext()
        request.options = options
        return try [UInt8](request.serializedData())
    }

    /// Decode a `runanywhere.v1.HybridSttTranscribeResponse` into the public
    /// result, raising the native rc as an `SDKException` when non-zero.
    private func decodeResponse(_ data: Data) throws -> HybridTranscribeResult {
        let response = try RAHybridSttTranscribeResponse(serializedBytes: data)

        guard response.rc == 0 else {
            let message = response.errorMsg.isEmpty
                ? "Hybrid STT transcribe failed (rc=\(response.rc))"
                : response.errorMsg
            throw SDKException(
                code: .serviceNotAvailable,
                message: message,
                category: .component
            )
        }

        return HybridTranscribeResult(
            text: response.text,
            detectedLanguage: response.detectedLanguage,
            routing: response.routing
        )
    }

    /// Cancel an in-flight transcribe, if any. (Best-effort: no STT engine
    /// exposes a cancel op today, so commons treats this as a no-op until one
    /// does — see rac_stt_hybrid_router_cancel.)
    public func cancel() {
        guard let handle = state.withLock({ $0.handle }) else { return }
        _ = rac_stt_hybrid_router_cancel(handle)
    }

    // MARK: - Teardown

    /// Detach + destroy both services, unregister custom filters, and destroy
    /// the router handle. Idempotent.
    public func close() {
        let teardown: (handle: rac_handle_t?, names: [String]) = state.withLock { current in
            let captured = (current.handle, current.customFilterNames)
            return captured
        }

        if let handle = teardown.handle {
            clearAndDestroyServices(handle: handle)
            rac_stt_hybrid_router_destroy(handle)
        }
        for name in teardown.names {
            HybridCustomFilter.unregister(name: name)
        }
        state.withLock { current in
            current.handle = nil
            current.customFilterNames = []
        }
    }

    deinit {
        close()
    }

    // MARK: - Registry-routed service creation

    /// Create an STT service for `model` via the registry route, then wrap the
    /// backend impl in a heap-stable `rac_stt_service_t` the router can hold a
    /// pointer to.
    ///
    /// Route → create: `rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, 0, hint)`
    /// selects the plugin (pinned to "sherpa"/"cloud" by backend), then
    /// `vt->stt_ops->create(model_id, config_json, &impl)` builds the backend
    /// instance — the same path every commons STT consumer uses.
    private func createService(for model: HybridModel) throws -> AttachedService {
        if model.backend == .hybridBackendSherpa {
            try requireSherpaRegistered()
        }

        let engineName = pinnedEngineName(for: model.backend)

        // Pin the named engine (offline "sherpa" vs cloud "cloud") — simple
        // priority order cannot distinguish two TRANSCRIBE plugins, so select
        // by name via the commons helper.
        let vtable: UnsafePointer<rac_engine_vtable_t>? = engineName.withCString { namePtr in
            rac_plugin_find_for_engine(RAC_PRIMITIVE_TRANSCRIBE, namePtr)
        }

        guard let vtable, let sttOps = vtable.pointee.stt_ops else {
            throw SDKException(
                code: .serviceNotAvailable,
                message: "No '\(engineName)' STT plugin registered. Register the "
                    + "backend first (ONNX.register() for sherpa, Cloud.register() for cloud).",
                category: .component
            )
        }
        guard let create = sttOps.pointee.create else {
            throw SDKException(
                code: .serviceNotAvailable,
                message: "'\(engineName)' STT plugin exposes no create op",
                category: .component
            )
        }

        // Resolve the per-backend config JSON the create op consumes. cloud
        // needs provider + api_key + model from the credential registry; sherpa
        // resolves its model from the C model registry, so it gets the model id
        // with no extra config.
        let configJSON: String? = try model.backend == .cloud
            ? Cloud.configJSON(for: model.id)
            : nil

        var impl: UnsafeMutableRawPointer?
        let createRC = model.id.withCString { modelIdPtr -> rac_result_t in
            if let configJSON {
                return configJSON.withCString { cfgPtr in
                    create(modelIdPtr, cfgPtr, &impl)
                }
            }
            return create(modelIdPtr, nil, &impl)
        }

        guard createRC == RAC_SUCCESS, let impl else {
            throw SDKException(
                code: .serviceNotAvailable,
                message: "'\(engineName)' STT create failed for model "
                    + "'\(model.id)' (rc=\(createRC))",
                category: .component
            )
        }

        // Heap-stable storage for the service struct + its model_id, both of
        // which the router dereferences for the router's lifetime.
        guard let modelIdCStr = strdup(model.id) else {
            sttOps.pointee.destroy?(impl)
            throw SDKException(
                code: .serviceNotAvailable, message: "strdup(model id) failed",
                category: .internal
            )
        }
        let servicePtr = UnsafeMutablePointer<rac_stt_service_t>.allocate(capacity: 1)
        servicePtr.initialize(to: rac_stt_service_t(
            ops: sttOps, impl: impl, model_id: UnsafePointer(modelIdCStr)
        ))

        return AttachedService(servicePtr: servicePtr, ops: sttOps, modelIdCStr: modelIdCStr)
    }

    /// Fail early with an actionable message when the on-device sherpa plugin
    /// isn't in the native plugin registry yet. Without this guard the offline
    /// service create bottoms out in an opaque vtable lookup
    /// (`rac_plugin_find_for_engine` returning NULL) that gives no hint about
    /// the missing prerequisite. Mirrors Kotlin's
    /// `HybridRouterBridgeAdapter.requireSherpaRegistered()`.
    ///
    /// The sherpa engine registers under the name "sherpa" when the ONNX
    /// backend module is folded in (`ONNX.register()` →
    /// `rac_backend_sherpa_register`), which must run before
    /// `HybridSTTRouter().setPair(...)`.
    private func requireSherpaRegistered() throws {
        let names = RunAnywhere.pluginLoader.registeredNames()
        guard names.contains(where: { $0.caseInsensitiveCompare("sherpa") == .orderedSame }) else {
            throw SDKException(
                code: .serviceNotAvailable,
                message: "sherpa STT backend is not registered. Load the on-device backend first "
                    + "(ONNX.register() for sherpa, Cloud.register() for cloud) before "
                    + "HybridSTTRouter().setPair(...). "
                    + "Registered plugins: \(names.isEmpty ? "(none)" : names.joined(separator: ", "))",
                category: .component
            )
        }
    }

    /// Map a backend kind to the plugin name `rac_plugin_route` pins on.
    private func pinnedEngineName(for backend: HybridBackendKind) -> String {
        switch backend {
        case .hybridBackendSherpa: return "sherpa"
        case .hybridBackendCloud: return "cloud"
        case .hybridBackendLlamacpp: return "llamacpp"
        case .hybridBackendOpenrouter: return "openrouter"
        case .hybridBackendUnspecified, .UNRECOGNIZED: return ""
        }
    }

    /// Clear both router slots, then destroy whatever services were attached.
    /// Slot-clearing must precede service destruction (router holds raw
    /// pointers — see rac_stt_hybrid_router.h UAF note).
    private func clearAndDestroyServices(handle: rac_handle_t) {
        _ = rac_stt_hybrid_router_set_offline_service_proto(handle, nil, nil, 0)
        _ = rac_stt_hybrid_router_set_online_service_proto(handle, nil, nil, 0)
        let services: (offline: AttachedService?, online: AttachedService?) =
            state.withLock { current in
                let captured = (current.offline, current.online)
                current.offline = nil
                current.online = nil
                return captured
            }
        if let offline = services.offline { destroy(offline) }
        if let online = services.online { destroy(online) }
    }

    /// Destroy one backend service (engine `destroy(impl)`) and free its
    /// heap-stable wrapper + model id.
    private func destroy(_ service: AttachedService) {
        service.ops.pointee.destroy?(service.servicePtr.pointee.impl)
        service.servicePtr.deinitialize(count: 1)
        service.servicePtr.deallocate()
        free(service.modelIdCStr)
    }

    private func notOpen() -> SDKException {
        SDKException(
            code: .notInitialized,
            message: "HybridSTTRouter is closed",
            category: .component
        )
    }
}
