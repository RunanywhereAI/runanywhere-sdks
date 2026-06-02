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
//    4. drives the router's transcribe and decodes the response.
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
/// let result = try router.transcribe(audio, options: .init(audioFormat: 1))
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

        // Encode each descriptor once; the router copies the bytes into its own
        // storage, so the local array only needs to outlive the call.
        let offlineDescriptor = offline.descriptorBytes()
        let onlineDescriptor = online.descriptorBytes()

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

        let policyBytes = policy.serializedBytes()
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
    public func transcribe(
        _ audio: Data,
        options: HybridTranscribeOptions = .init()
    ) throws -> HybridTranscribeResult {
        guard let handle = state.withLock({ $0.handle }) else {
            throw notOpen()
        }

        let requestBytes = HybridSTTWire.encodeRequest(audio: [UInt8](audio), options: options)

        var outBytes: UnsafeMutablePointer<UInt8>?
        var outSize: Int = 0
        let rc = rac_stt_hybrid_router_transcribe_proto(
            handle, requestBytes, requestBytes.count, &outBytes, &outSize
        )

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

        let responseBytes = Array(UnsafeBufferPointer(start: outBytes, count: outSize))
        return try HybridSTTWire.decodeResponse(responseBytes)
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
        let engineName = pinnedEngineName(for: model.backend)

        var vtable: UnsafePointer<rac_engine_vtable_t>?
        let routeRC = engineName.withCString { namePtr -> rac_result_t in
            var hints = rac_routing_hints_t()
            hints.preferred_engine_name = namePtr   // hard pin to this engine
            hints.no_fallback = 1                    // fail if the pinned engine is absent
            return rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, 0, &hints, &vtable)
        }

        guard routeRC == RAC_SUCCESS, let vtable, let sttOps = vtable.pointee.stt_ops else {
            throw SDKException(
                code: .serviceNotAvailable,
                message: "No '\(engineName)' STT plugin registered "
                    + "(rc=\(routeRC)). Register the backend first "
                    + "(ONNX.register() for sherpa, Cloud.register() for cloud).",
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

    /// Map a backend kind to the plugin name `rac_plugin_route` pins on.
    private func pinnedEngineName(for backend: HybridBackendKind) -> String {
        switch backend {
        case .sherpa: return "sherpa"
        case .cloud: return "cloud"
        case .llamacpp: return "llamacpp"
        case .openrouter: return "openrouter"
        case .unspecified: return ""
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
