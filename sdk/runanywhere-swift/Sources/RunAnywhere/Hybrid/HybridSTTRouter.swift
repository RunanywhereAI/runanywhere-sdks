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
//    4. drives the router's transcribe and decodes the response (raw-PCM16 →
//       WAV normalisation happens inside the commons router so one payload
//       serves both services).
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

    private struct PreparedPair: @unchecked Sendable {
        let offline: AttachedService
        let online: AttachedService
        let offlineDescriptor: [UInt8]
        let onlineDescriptor: [UInt8]
        let policyBytes: [UInt8]
    }

    /// `@unchecked Sendable`: every field is mutated only under the `state`
    /// lock; the native handle + service pointers never escape it unguarded.
    private struct State: @unchecked Sendable {
        var handle: rac_handle_t?
        var offline: AttachedService?
        var online: AttachedService?
        var isReconfiguring = false
        /// Names of custom-filter predicates registered for the current policy,
        /// so `close()` can unregister exactly those.
        var customFilterNames: [String] = []
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let activeOperations = DispatchGroup()

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
        state.withLockUnchecked { $0.handle = handle }
    }

    // MARK: - Pair + policy

    /// Bind the offline + online models, install the policy, and register any
    /// custom-filter predicates. Replaces any previous pairing.
    public func setPair(
        offline: HybridModel,
        online: HybridModel,
        policy: HybridRoutingPolicy
    ) throws {
        guard state.withLock({ $0.handle != nil }) else {
            throw notOpen()
        }

        let prepared = try preparePair(offline: offline, online: online, policy: policy)

        let canReconfigure = state.withLock { current -> Bool in
            guard current.handle != nil, !current.isReconfiguring else { return false }
            current.isReconfiguring = true
            return true
        }
        guard canReconfigure else {
            destroy(prepared.offline)
            destroy(prepared.online)
            throw SDKException(
                code: .serviceBusy,
                message: "Hybrid STT router is closed or already being reconfigured",
                category: .component
            )
        }
        activeOperations.wait()
        defer { state.withLock { $0.isReconfiguring = false } }

        try installPair(prepared, policy: policy)
    }

    private func preparePair(
        offline: HybridModel,
        online: HybridModel,
        policy: HybridRoutingPolicy
    ) throws -> PreparedPair {
        let offlineService = try createService(for: offline)
        let onlineService: AttachedService
        do {
            onlineService = try createService(for: online)
        } catch {
            destroy(offlineService)
            throw error
        }

        do {
            return PreparedPair(
                offline: offlineService,
                online: onlineService,
                offlineDescriptor: try offline.descriptorBytes(),
                onlineDescriptor: try online.descriptorBytes(),
                policyBytes: try policy.serializedBytes()
            )
        } catch {
            destroy(offlineService)
            destroy(onlineService)
            throw error
        }
    }

    private func installPair(
        _ prepared: PreparedPair,
        policy: HybridRoutingPolicy
    ) throws {
        try state.withLockUnchecked { current in
            guard let handle = current.handle else {
                destroy(prepared.offline)
                destroy(prepared.online)
                throw notOpen()
            }

            // Keep the lock for the full native swap. `close()` and
            // `transcribe()` therefore cannot destroy or use a half-installed
            // router/service pair.
            clearAndDestroyServices(handle: handle, state: &current)
            retirePreviousCustomFilters(state: &current)

            let rcOff = rac_stt_hybrid_router_set_offline_service_proto(
                handle,
                prepared.offline.servicePtr,
                prepared.offlineDescriptor,
                prepared.offlineDescriptor.count
            )
            guard rcOff == RAC_SUCCESS else {
                destroy(prepared.offline)
                destroy(prepared.online)
                throw SDKException(
                    code: .serviceNotAvailable,
                    message: "set_offline_service_proto failed (rc=\(rcOff))",
                    category: .component
                )
            }
            let rcOn = rac_stt_hybrid_router_set_online_service_proto(
                handle,
                prepared.online.servicePtr,
                prepared.onlineDescriptor,
                prepared.onlineDescriptor.count
            )
            guard rcOn == RAC_SUCCESS else {
                _ = rac_stt_hybrid_router_set_offline_service_proto(handle, nil, nil, 0)
                destroy(prepared.offline)
                destroy(prepared.online)
                throw SDKException(
                    code: .serviceNotAvailable,
                    message: "set_online_service_proto failed (rc=\(rcOn))",
                    category: .component
                )
            }

            // Register predicates before installing policy bytes so commons can
            // resolve every named custom filter on its first evaluation.
            let customNames = policy.customFilters.map(\.name)
            for filter in policy.customFilters {
                HybridCustomFilter.register(name: filter.name, check: filter.check)
            }

            let rcPolicy = rac_stt_hybrid_router_set_policy_proto(
                handle, prepared.policyBytes, prepared.policyBytes.count
            )
            guard rcPolicy == RAC_SUCCESS else {
                for name in customNames { HybridCustomFilter.unregister(name: name) }
                _ = rac_stt_hybrid_router_set_offline_service_proto(handle, nil, nil, 0)
                _ = rac_stt_hybrid_router_set_online_service_proto(handle, nil, nil, 0)
                destroy(prepared.offline)
                destroy(prepared.online)
                throw SDKException(
                    code: .serviceNotAvailable,
                    message: "set_policy_proto failed (rc=\(rcPolicy))",
                    category: .component
                )
            }

            current.offline = prepared.offline
            current.online = prepared.online
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
    ///     (wav/mp3/flac/...). Raw PCM16 is wrapped in a WAV container by the
    ///     commons router (rac_stt_hybrid_router_proto.cpp); WAV input
    ///     (RIFF/WAVE magic) and declared compressed formats pass through
    ///     unchanged.
    ///   - options: Optional language / sample-rate / audio-format hints
    ///     (proto-typed `HybridTranscribeOptions`).
    public func transcribe(
        _ audio: Data,
        options: HybridTranscribeOptions = .init()
    ) throws -> HybridTranscribeResult {
        let requestBytes = try encodeRequest(audio: audio, options: options)
        let handle = try beginOperation()
        defer { activeOperations.leave() }

        var outBytes: UnsafeMutablePointer<UInt8>?
        var outSize: Int = 0
        let rc = requestBytes.withUnsafeBufferPointer { buffer in
            rac_stt_hybrid_router_transcribe_proto(
                handle.rawValue, buffer.baseAddress, buffer.count, &outBytes, &outSize
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

        return try decodeResponse(Data(bytes: outBytes, count: outSize))
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
        guard let handle = try? beginOperation() else { return }
        defer { activeOperations.leave() }
        _ = rac_stt_hybrid_router_cancel(handle.rawValue)
    }

    // MARK: - Teardown

    /// Detach + destroy both services, unregister custom filters, and destroy
    /// the router handle. Idempotent.
    public func close() {
        let closingHandle = state.withLockUnchecked { current -> HybridRouterHandle? in
            guard let handle = current.handle else { return nil }
            current.handle = nil
            return HybridRouterHandle(rawValue: handle)
        }
        guard let closingHandle else { return }

        // No new operation can start after the handle is cleared. Wait for any
        // transcribe/cancel that already borrowed it before freeing services.
        activeOperations.wait()

        let names = state.withLockUnchecked { current -> [String] in
            clearAndDestroyServices(handle: closingHandle.rawValue, state: &current)
            rac_stt_hybrid_router_destroy(closingHandle.rawValue)
            let names = current.customFilterNames
            current.customFilterNames = []
            return names
        }
        for name in names {
            HybridCustomFilter.unregister(name: name)
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
                code: .serviceNotAvailable,
                message: "strdup(model id) failed",
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
    private func clearAndDestroyServices(handle: rac_handle_t, state: inout State) {
        _ = rac_stt_hybrid_router_set_offline_service_proto(handle, nil, nil, 0)
        _ = rac_stt_hybrid_router_set_online_service_proto(handle, nil, nil, 0)
        let services = (offline: state.offline, online: state.online)
        state.offline = nil
        state.online = nil
        if let offline = services.offline { destroy(offline) }
        if let online = services.online { destroy(online) }
    }

    /// Retire the previous policy's custom-filter predicates so re-pairing
    /// with a different policy doesn't leave stale named filters registered
    /// in commons. Verbatim extraction from `setPair` (lint body-length).
    private func retirePreviousCustomFilters(state: inout State) {
        let previousFilterNames = state.customFilterNames
        state.customFilterNames = []
        for name in previousFilterNames { HybridCustomFilter.unregister(name: name) }
    }

    /// Destroy one backend service (engine `destroy(impl)`) and free its
    /// heap-stable wrapper + model id.
    private func destroy(_ service: AttachedService) {
        service.ops.pointee.destroy?(service.servicePtr.pointee.impl)
        service.servicePtr.deinitialize(count: 1)
        service.servicePtr.deallocate()
        free(service.modelIdCStr)
    }

    /// Borrow the router handle for one native operation. Entering the dispatch
    /// group under the state lock closes the race with `close()` clearing the
    /// handle; `close()` waits for every successful borrow before destroy.
    private func beginOperation() throws -> HybridRouterHandle {
        try state.withLockUnchecked { current in
            guard let handle = current.handle, !current.isReconfiguring else {
                throw notOpen()
            }
            activeOperations.enter()
            return HybridRouterHandle(rawValue: handle)
        }
    }

    private func notOpen() -> SDKException {
        SDKException(
            code: .notInitialized,
            message: "HybridSTTRouter is closed",
            category: .component
        )
    }
}

/// Borrowed native router pointer whose lifetime is guarded by
/// `HybridSTTRouter.activeOperations`.
private struct HybridRouterHandle: @unchecked Sendable {
    let rawValue: rac_handle_t
}
