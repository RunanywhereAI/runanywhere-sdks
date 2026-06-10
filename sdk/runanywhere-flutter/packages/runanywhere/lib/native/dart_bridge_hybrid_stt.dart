// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_hybrid_stt.dart — FFI bridge for the STT hybrid router.
//
// Owns ALL `dart:ffi` work for the hybrid STT router so the public binding
// under `lib/public/hybrid/` stays free of FFI imports (canonical §15
// type-discipline, matching every other capability/bridge split in this SDK).
//
// THIN by construction — commons owns the entire routing decision (hard-filter
// eligibility incl. custom-filter callbacks, ranking, confidence cascade, and
// primary→secondary fallback all live in rac_stt_hybrid_router.cpp). This file
// only:
//   1. allocates / destroys the router handle
//      (rac_stt_hybrid_router_create / _destroy),
//   2. creates the two STT services through the SAME registry-routed creation
//      path commons uses (rac_plugin_find_for_engine(RAC_PRIMITIVE_TRANSCRIBE,
//      engineName) → vt->stt_ops->create → wrap in a heap-stable
//      rac_stt_service_t), pinning the engine by name ("sherpa" / "cloud"),
//   3. attaches each service + its serialized HybridModelDescriptor bytes
//      (rac_stt_hybrid_router_set_{offline,online}_service_proto),
//   4. installs the serialized HybridRoutingPolicy bytes
//      (rac_stt_hybrid_router_set_policy_proto),
//   5. installs the cross-SDK device-state vtable
//      (rac_hybrid_set_device_state) and named custom-filter predicates
//      (rac_hybrid_register_custom_filter / _unregister) as Dart→C callbacks,
//   6. dispatches one transcribe (rac_stt_hybrid_router_transcribe_proto) and
//      returns the raw response bytes (decoded by the generated Dart proto in
//      the public layer).
//
// Mirrors the Kotlin HybridRouterBridgeAdapter + RunAnywhereBridge JNI thunks
// (create_stt_service_via_registry) and the Swift HybridSTTRouter's
// rac_plugin_find_for_engine → stt_ops->create dance, adapted to Dart FFI.
//
// Service-creation note: the JNI helper `racSttHybridRouterCreateService` is a
// `Java_...` thunk, not a C ABI export, so Flutter FFI cannot call it. Instead
// this bridge replicates its body in pure FFI (route → vtable slot →
// stt_ops->create → build rac_stt_service_t) over faithful Dart mirrors of the
// commons structs. The struct mirrors track plugin ABI v3
// (RAC_PLUGIN_API_VERSION = 3); a layout bump there requires updating them.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

// ============================================================================
// Primitive enum value (rac/plugin/rac_primitive.h)
// ============================================================================

/// `RAC_PRIMITIVE_TRANSCRIBE` — the speech-to-text primitive the router pins
/// every service-creation route to.
const int _kPrimitiveTranscribe = 2;

// ============================================================================
// FFI structs mirroring the commons C ABI (plugin ABI v3).
//
// Only the prefix needed to reach `stt_ops` (in the engine vtable) and the
// `create` / `destroy` slots (in the STT ops vtable) is consumed; the full
// field list is mirrored so Dart's Struct layout reproduces the C alignment /
// padding exactly and the consumed offsets are correct.
// ============================================================================

/// Mirrors `rac_engine_metadata_t` (rac/plugin/rac_engine_vtable.h). Consumed
/// only as the leading block of `_RacEngineVtable` so `sttOps` lands at the
/// correct offset.
final class _RacEngineMetadata extends Struct {
  @Uint32()
  external int abiVersion;

  external Pointer<Utf8> name;
  external Pointer<Utf8> displayName;
  external Pointer<Utf8> engineVersion;

  @Int32()
  external int priority;

  @Uint64()
  external int capabilityFlags;

  external Pointer<Int32> runtimes;

  @Size()
  external int runtimesCount;

  external Pointer<Uint32> formats;

  @Size()
  external int formatsCount;
}

/// Mirrors `rac_engine_vtable_t`. The metadata block is embedded by value;
/// `capabilityCheck` / `onUnload` are function pointers, then the eight active
/// primitive op-pointer slots, then ten reserved `const void*` slots. Only
/// `sttOps` is dereferenced.
final class _RacEngineVtable extends Struct {
  external _RacEngineMetadata metadata;

  external Pointer<NativeFunction<Int32 Function()>> capabilityCheck;
  external Pointer<NativeFunction<Void Function()>> onUnload;

  external Pointer<Void> llmOps;
  external Pointer<_RacSttServiceOps> sttOps;
  external Pointer<Void> ttsOps;
  external Pointer<Void> vadOps;
  external Pointer<Void> embeddingOps;
  external Pointer<Void> rerankOps;
  external Pointer<Void> vlmOps;
  external Pointer<Void> diffusionOps;

  external Pointer<Void> reservedSlot0;
  external Pointer<Void> reservedSlot1;
  external Pointer<Void> reservedSlot2;
  external Pointer<Void> reservedSlot3;
  external Pointer<Void> reservedSlot4;
  external Pointer<Void> reservedSlot5;
  external Pointer<Void> reservedSlot6;
  external Pointer<Void> reservedSlot7;
  external Pointer<Void> reservedSlot8;
  external Pointer<Void> reservedSlot9;
}

/// `rac_result_t (*create)(const char* model_id, const char* config_json,
/// void** out_impl)`.
typedef _SttCreateNative = Int32 Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Pointer<Void>>);

/// `void (*destroy)(void* impl)`.
typedef _SttDestroyNative = Void Function(Pointer<Void>);

/// Mirrors `rac_stt_service_ops_t` (rac/features/stt/rac_stt_service.h). Slot
/// order is load-bearing: `destroy` is index 5, `create` is index 6. The
/// trailing slots are mirrored so the two consumed ones sit at the right
/// offsets, but never dereferenced from Dart.
final class _RacSttServiceOps extends Struct {
  external Pointer<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>)>>
      initialize;
  external Pointer<
          NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<Void>, Size, Pointer<Void>,
                  Pointer<Void>)>>
      transcribe;
  external Pointer<
          NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<Void>, Size, Pointer<Void>,
                  Pointer<Void>, Pointer<Void>)>>
      transcribeStream;
  external Pointer<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>)>>
      getInfo;
  external Pointer<NativeFunction<Int32 Function(Pointer<Void>)>> cleanup;
  external Pointer<NativeFunction<_SttDestroyNative>> destroy;
  external Pointer<NativeFunction<_SttCreateNative>> create;
  external Pointer<
          NativeFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>)>>
      getLanguages;
  external Pointer<
          NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<Void>, Size, Pointer<Void>,
                  Pointer<Pointer<Utf8>>)>>
      detectLanguage;
  external Pointer<
          NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)>>
      streamCreate;
  external Pointer<
          NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Int16>, Size,
                  Pointer<Void>, Pointer<Void>)>>
      streamFeedAudioChunk;
  external Pointer<
          NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>)>>
      streamDestroy;
}

/// Mirrors `rac_stt_service_t` — {ops, impl, model_id}. Built by this bridge
/// and handed to the router's set_*_service_proto setters as an opaque pointer.
final class _RacSttService extends Struct {
  external Pointer<_RacSttServiceOps> ops;
  external Pointer<Void> impl;
  external Pointer<Utf8> modelId;
}

// ============================================================================
// Device-state vtable (rac/router/hybrid/rac_hybrid_device_state.h)
// ============================================================================

/// `bool (*is_online)(void* user_data)` — bool is one byte in the C ABI; FFI
/// models it as Uint8.
typedef _HybridIsOnlineNative = Uint8 Function(Pointer<Void>);

/// `int32_t (*battery_percent)(void* user_data)`.
typedef _HybridBatteryPercentNative = Int32 Function(Pointer<Void>);

/// `bool (*is_thermal_throttled)(void* user_data)`.
typedef _HybridThermalThrottledNative = Uint8 Function(Pointer<Void>);

/// Mirrors `rac_hybrid_device_state_ops_t`.
final class _RacHybridDeviceStateOps extends Struct {
  external Pointer<NativeFunction<_HybridIsOnlineNative>> isOnline;
  external Pointer<NativeFunction<_HybridBatteryPercentNative>> batteryPercent;
  external Pointer<NativeFunction<_HybridThermalThrottledNative>>
      isThermalThrottled;
  external Pointer<Void> userData;
}

// ============================================================================
// Custom-filter predicate (rac/router/hybrid/rac_hybrid_custom_filter.h)
// ============================================================================

/// Mirrors `rac_hybrid_routing_context_t` — {is_online, battery_percent,
/// candidate_model_id[128]}. The router rewrites `candidateModelId` to the
/// candidate under evaluation before invoking a predicate.
final class _RacHybridRoutingContext extends Struct {
  @Uint8()
  external int isOnline;

  @Int32()
  external int batteryPercent;

  @Array(128)
  external Array<Uint8> candidateModelId;
}

/// `rac_bool_t (*predicate)(const rac_hybrid_routing_context_t* ctx,
/// void* user_data)`.
typedef _HybridCustomFilterPredicateNative = Int32 Function(
    Pointer<_RacHybridRoutingContext>, Pointer<Void>);

// ============================================================================
// Proto-byte router ABI (rac/router/hybrid/rac_stt_hybrid_router_proto.h)
// ============================================================================

typedef _RouterCreateNative = Int32 Function(Pointer<RacHandle>);
typedef _RouterCreateDart = int Function(Pointer<RacHandle>);

typedef _RouterDestroyNative = Void Function(RacHandle);
typedef _RouterDestroyDart = void Function(RacHandle);

typedef _RouterCancelNative = Int32 Function(RacHandle);
typedef _RouterCancelDart = int Function(RacHandle);

typedef _RouterSetServiceProtoNative = Int32 Function(
    RacHandle, Pointer<Void>, Pointer<Uint8>, Size);
typedef _RouterSetServiceProtoDart = int Function(
    RacHandle, Pointer<Void>, Pointer<Uint8>, int);

typedef _RouterSetPolicyProtoNative = Int32 Function(
    RacHandle, Pointer<Uint8>, Size);
typedef _RouterSetPolicyProtoDart = int Function(
    RacHandle, Pointer<Uint8>, int);

typedef _RouterTranscribeProtoNative = Int32 Function(
    RacHandle, Pointer<Uint8>, Size, Pointer<Pointer<Uint8>>, Pointer<Size>);
typedef _RouterTranscribeProtoDart = int Function(
    RacHandle, Pointer<Uint8>, int, Pointer<Pointer<Uint8>>, Pointer<Size>);

typedef _RouterProtoBufferFreeNative = Void Function(Pointer<Uint8>);
typedef _RouterProtoBufferFreeDart = void Function(Pointer<Uint8>);

typedef _FindForEngineNative = Pointer<_RacEngineVtable> Function(
    Int32, Pointer<Utf8>);
typedef _FindForEngineDart = Pointer<_RacEngineVtable> Function(
    int, Pointer<Utf8>);

typedef _HybridSetDeviceStateNative = Int32 Function(
    Pointer<_RacHybridDeviceStateOps>);
typedef _HybridSetDeviceStateDart = int Function(
    Pointer<_RacHybridDeviceStateOps>);

typedef _HybridRegisterCustomFilterNative = Int32 Function(
    Pointer<Utf8>,
    Pointer<NativeFunction<_HybridCustomFilterPredicateNative>>,
    Pointer<Void>);
typedef _HybridRegisterCustomFilterDart = int Function(
    Pointer<Utf8>,
    Pointer<NativeFunction<_HybridCustomFilterPredicateNative>>,
    Pointer<Void>);

typedef _HybridUnregisterCustomFilterNative = Int32 Function(Pointer<Utf8>);
typedef _HybridUnregisterCustomFilterDart = int Function(Pointer<Utf8>);

typedef _CloudRegisterNative = Int32 Function();
typedef _CloudRegisterDart = int Function();

/// Opaque handle to a native STT service the router holds by pointer: the heap
/// `rac_stt_service_t` the setters receive, plus the strdup'd model id the
/// struct points at — both freed in [DartBridgeHybridStt.destroyService]. The
/// public router treats this as an opaque token; only this bridge dereferences
/// it.
class HybridServiceHandle {
  HybridServiceHandle._(this._servicePtr, this._modelIdPtr);

  final Pointer<_RacSttService> _servicePtr;
  final Pointer<Utf8> _modelIdPtr;
}

/// FFI bridge to the commons STT hybrid router + cloud registration.
/// Stateless beyond cached function lookups; the public `HybridSttRouter`
/// owns the handles.
class DartBridgeHybridStt {
  DartBridgeHybridStt._();

  static final DartBridgeHybridStt instance = DartBridgeHybridStt._();

  static final _logger = SDKLogger('DartBridge.HybridStt');

  static DynamicLibrary get _lib => PlatformLoader.loadCommons();

  // --- Cached lookups (resolved once on first access) ----------------------

  static final _RouterCreateDart _routerCreate =
      _lib.lookupFunction<_RouterCreateNative, _RouterCreateDart>(
          'rac_stt_hybrid_router_create');

  static final _RouterDestroyDart _routerDestroy =
      _lib.lookupFunction<_RouterDestroyNative, _RouterDestroyDart>(
          'rac_stt_hybrid_router_destroy');

  // Best-effort cancel — same (handle) -> result shape; resolved lazily so
  // older packaged commons without the symbol degrade to a no-op.
  static final _RouterCancelDart? _routerCancel = (() {
    try {
      return _lib.lookupFunction<_RouterCancelNative, _RouterCancelDart>(
          'rac_stt_hybrid_router_cancel');
    } catch (_) {
      return null;
    }
  })();

  static final _RouterSetServiceProtoDart _setOfflineServiceProto =
      _lib.lookupFunction<_RouterSetServiceProtoNative,
              _RouterSetServiceProtoDart>(
          'rac_stt_hybrid_router_set_offline_service_proto');

  static final _RouterSetServiceProtoDart _setOnlineServiceProto =
      _lib.lookupFunction<_RouterSetServiceProtoNative,
              _RouterSetServiceProtoDart>(
          'rac_stt_hybrid_router_set_online_service_proto');

  static final _RouterSetPolicyProtoDart _setPolicyProto = _lib.lookupFunction<
      _RouterSetPolicyProtoNative,
      _RouterSetPolicyProtoDart>('rac_stt_hybrid_router_set_policy_proto');

  static final _RouterTranscribeProtoDart _transcribeProto =
      _lib.lookupFunction<_RouterTranscribeProtoNative,
          _RouterTranscribeProtoDart>('rac_stt_hybrid_router_transcribe_proto');

  static final _RouterProtoBufferFreeDart _protoBufferFree =
      _lib.lookupFunction<_RouterProtoBufferFreeNative,
              _RouterProtoBufferFreeDart>(
          'rac_stt_hybrid_router_proto_buffer_free');

  static final _FindForEngineDart _pluginFindForEngine =
      _lib.lookupFunction<_FindForEngineNative, _FindForEngineDart>(
          'rac_plugin_find_for_engine');

  static final _HybridSetDeviceStateDart _setDeviceState = _lib.lookupFunction<
      _HybridSetDeviceStateNative,
      _HybridSetDeviceStateDart>('rac_hybrid_set_device_state');

  static final _HybridRegisterCustomFilterDart _registerCustomFilter =
      _lib.lookupFunction<_HybridRegisterCustomFilterNative,
          _HybridRegisterCustomFilterDart>('rac_hybrid_register_custom_filter');

  static final _HybridUnregisterCustomFilterDart _unregisterCustomFilter =
      _lib.lookupFunction<_HybridUnregisterCustomFilterNative,
              _HybridUnregisterCustomFilterDart>(
          'rac_hybrid_unregister_custom_filter');

  // --- Router lifecycle ----------------------------------------------------

  /// Allocate a native router handle. Throws [StateError] on failure.
  RacHandle createRouter() {
    final out = calloc<RacHandle>();
    try {
      final rc = _routerCreate(out);
      final handle = out.value;
      if (rc != RAC_SUCCESS || handle == nullptr) {
        throw StateError('rac_stt_hybrid_router_create failed (rc=$rc)');
      }
      return handle;
    } finally {
      calloc.free(out);
    }
  }

  /// Destroy a router handle. The wrapped services are NOT freed here — callers
  /// clear the slots + [destroyService] them first (see header UAF note).
  /// Cancel an in-flight transcribe, if any. Best-effort: commons treats
  /// this as a no-op until an STT engine exposes a cancel op (see
  /// rac_stt_hybrid_router_cancel). Mirrors Swift HybridSTTRouter.cancel().
  void cancelRouter(RacHandle handle) {
    final cancelFn = _routerCancel;
    if (cancelFn == null) {
      _logger.debug('rac_stt_hybrid_router_cancel unavailable');
      return;
    }
    cancelFn(handle);
  }

  void destroyRouter(RacHandle handle) {
    if (handle == nullptr) {
      return;
    }
    _routerDestroy(handle);
  }

  // --- Registry-routed service creation ------------------------------------

  /// Create an STT service via the plugin registry, pinning [engineHint]
  /// ("sherpa" / "cloud") as the engine name passed to
  /// `rac_plugin_find_for_engine` and forwarding [modelIdOrPath] + [configJson]
  /// to the routed engine's `stt_ops->create`. Wraps the backend impl in a
  /// heap-stable `rac_stt_service_t` the router can hold by pointer. Throws
  /// [StateError] on lookup/create failure.
  ///
  /// Mirrors commons' `create_stt_service_via_registry` exactly (route → slot →
  /// create → wrap), the single creation path BOTH router sides use.
  HybridServiceHandle createService({
    required String engineHint,
    String modelIdOrPath = '',
    String? configJson,
  }) {
    final hintPtr = engineHint.toNativeUtf8();
    try {
      final vtable = _pluginFindForEngine(_kPrimitiveTranscribe, hintPtr);
      if (vtable == nullptr) {
        throw StateError(
          "No '$engineHint' STT plugin registered. Register the "
          'backend first (the on-device sherpa engine, or cloud via '
          'BACKEND.cloud.register / RunAnywhere.hybrid.registerCloud).',
        );
      }
      final sttOps = vtable.ref.sttOps;
      if (sttOps == nullptr || sttOps.ref.create == nullptr) {
        throw StateError("'$engineHint' STT plugin exposes no create op");
      }

      final modelIdPtr =
          modelIdOrPath.isEmpty ? nullptr : modelIdOrPath.toNativeUtf8();
      final configPtr =
          (configJson == null || configJson.isEmpty)
              ? nullptr
              : configJson.toNativeUtf8();
      final outImpl = calloc<Pointer<Void>>();
      try {
        final create = sttOps.ref.create.asFunction<
            int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Pointer<Void>>)>();
        final createRc = create(
          modelIdPtr.cast<Utf8>(),
          configPtr.cast<Utf8>(),
          outImpl,
        );
        final impl = outImpl.value;
        if (createRc != RAC_SUCCESS || impl == nullptr) {
          throw StateError(
            "'$engineHint' STT create failed for model "
            "'$modelIdOrPath' (rc=$createRc)",
          );
        }

        // Heap-stable storage for the service struct + a tag for logs (model id
        // when we have one, else the engine hint — matching commons).
        final tag = modelIdOrPath.isNotEmpty ? modelIdOrPath : engineHint;
        final tagPtr = tag.toNativeUtf8();
        final servicePtr = calloc<_RacSttService>();
        servicePtr.ref
          ..ops = sttOps
          ..impl = impl
          ..modelId = tagPtr;
        return HybridServiceHandle._(servicePtr, tagPtr);
      } finally {
        calloc.free(outImpl);
        if (modelIdPtr != nullptr) {
          calloc.free(modelIdPtr);
        }
        if (configPtr != nullptr) {
          calloc.free(configPtr);
        }
      }
    } finally {
      calloc.free(hintPtr);
    }
  }

  /// Destroy a service created by [createService]: run the engine's
  /// `stt_ops->destroy(impl)`, then free the heap wrapper + tag string. The
  /// router slot MUST be cleared first (see UAF note in the proto header).
  void destroyService(HybridServiceHandle? service) {
    if (service == null) {
      return;
    }
    final ops = service._servicePtr.ref.ops;
    final impl = service._servicePtr.ref.impl;
    if (ops != nullptr && ops.ref.destroy != nullptr && impl != nullptr) {
      final destroy = ops.ref.destroy.asFunction<void Function(Pointer<Void>)>();
      destroy(impl);
    }
    calloc.free(service._modelIdPtr);
    calloc.free(service._servicePtr);
  }

  // --- Slot setters + policy + transcribe ----------------------------------

  /// Attach (or detach when [service] is null) the offline-side service with
  /// its serialized HybridModelDescriptor bytes. Returns the native rc.
  int setOfflineService(
    RacHandle router,
    HybridServiceHandle? service,
    Uint8List descriptorBytes,
  ) =>
      _setService(_setOfflineServiceProto, router, service, descriptorBytes);

  /// Symmetric to [setOfflineService] for the online side.
  int setOnlineService(
    RacHandle router,
    HybridServiceHandle? service,
    Uint8List descriptorBytes,
  ) =>
      _setService(_setOnlineServiceProto, router, service, descriptorBytes);

  int _setService(
    _RouterSetServiceProtoDart fn,
    RacHandle router,
    HybridServiceHandle? service,
    Uint8List descriptorBytes,
  ) {
    final servicePtr =
        (service?._servicePtr ?? nullptr.cast<_RacSttService>()).cast<Void>();
    final bytesPtr = _copyBytes(descriptorBytes);
    try {
      return fn(router, servicePtr, bytesPtr, descriptorBytes.length);
    } finally {
      calloc.free(bytesPtr);
    }
  }

  /// Install the serialized HybridRoutingPolicy bytes. Returns the native rc.
  int setPolicy(RacHandle router, Uint8List policyBytes) {
    final bytesPtr = _copyBytes(policyBytes);
    try {
      return _setPolicyProto(router, bytesPtr, policyBytes.length);
    } finally {
      calloc.free(bytesPtr);
    }
  }

  /// Dispatch one transcribe request (serialized HybridSttTranscribeRequest)
  /// and return the serialized HybridSttTranscribeResponse bytes. Throws
  /// [StateError] when the native call fails or returns an empty envelope.
  Uint8List transcribe(RacHandle router, Uint8List requestBytes) {
    final reqPtr = _copyBytes(requestBytes);
    final outBytes = calloc<Pointer<Uint8>>();
    final outSize = calloc<Size>();
    try {
      final rc = _transcribeProto(
        router,
        reqPtr,
        requestBytes.length,
        outBytes,
        outSize,
      );
      final dataPtr = outBytes.value;
      final size = outSize.value;
      try {
        if (rc != RAC_SUCCESS || dataPtr == nullptr || size == 0) {
          throw StateError(
            'rac_stt_hybrid_router_transcribe_proto failed (rc=$rc)',
          );
        }
        // Copy out before freeing the native buffer.
        return Uint8List.fromList(dataPtr.asTypedList(size));
      } finally {
        if (dataPtr != nullptr) {
          _protoBufferFree(dataPtr);
        }
      }
    } finally {
      calloc.free(reqPtr);
      calloc.free(outBytes);
      calloc.free(outSize);
    }
  }

  // --- Device-state vtable -------------------------------------------------

  /// Install [provider] callbacks into the commons device-state vtable. Returns
  /// the native rc. Pass-through closures are wired into `Pointer.fromFunction`
  /// trampolines that read the single installed provider (see static fields).
  int setDeviceStateProvider(HybridDeviceStateCallbacks provider) {
    _installedDeviceState = provider;
    final ops = calloc<_RacHybridDeviceStateOps>();
    // Keep the ops struct alive for the vtable lifetime; commons copies it on
    // install, so freeing right after the call is also safe — but the trampoline
    // function pointers must stay resident (they are top-level functions, so
    // they always are).
    try {
      ops.ref
        ..isOnline = Pointer.fromFunction<_HybridIsOnlineNative>(
            _deviceIsOnlineTrampoline, 1)
        ..batteryPercent = Pointer.fromFunction<_HybridBatteryPercentNative>(
            _deviceBatteryTrampoline, 100)
        ..isThermalThrottled =
            Pointer.fromFunction<_HybridThermalThrottledNative>(
                _deviceThermalTrampoline, 0)
        ..userData = nullptr;
      return _setDeviceState(ops);
    } finally {
      calloc.free(ops);
    }
  }

  /// Detach the device-state provider, restoring the commons optimistic
  /// default. Returns the native rc.
  int clearDeviceStateProvider() {
    _installedDeviceState = null;
    return _setDeviceState(nullptr);
  }

  // --- Custom-filter predicates --------------------------------------------

  /// Register (or replace) a named custom-filter predicate. The predicate runs
  /// inside commons during candidate filtering; Dart only supplies the closure.
  /// Returns the native rc.
  int registerCustomFilter(String name, HybridCustomFilterCheck check) {
    _customFilters[name] = check;
    final namePtr = name.toNativeUtf8();
    try {
      return _registerCustomFilter(
        namePtr,
        Pointer.fromFunction<_HybridCustomFilterPredicateNative>(
            _customFilterTrampoline, RAC_TRUE),
        nullptr,
      );
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Unregister a named custom-filter predicate. Returns the native rc.
  int unregisterCustomFilter(String name) {
    _customFilters.remove(name);
    final namePtr = name.toNativeUtf8();
    try {
      return _unregisterCustomFilter(namePtr);
    } finally {
      calloc.free(namePtr);
    }
  }

  // --- cloud plugin registration -------------------------------------------

  /// Register the cloud engine with the commons plugin registry so it is
  /// routable via `rac_plugin_find_for_engine(TRANSCRIBE, "cloud")`. Tolerant of
  /// double-registration (RAC_ERROR_MODULE_ALREADY_REGISTERED is treated as
  /// success). Returns the native rc, or null when the symbol is unavailable in
  /// this build (e.g. cloud engine not linked into the loaded .so).
  ///
  /// Mirrors Kotlin `CloudBridge.nativeRegister` /
  /// Swift `CloudSTT.register` → `rac_backend_cloud_register`.
  int? registerCloud() {
    try {
      // On Android the register symbol is DEFINED in the standalone
      // librac_backend_cloud.so and only IMPORTED by the commons JNI lib, so it
      // must be dlopen'd before the lookup can resolve through `_lib`. No-op on
      // iOS/macOS (statically linked into the process). Tolerant of absence.
      PlatformLoader.ensureCloudBackendLoaded();
      final fn = _lib.lookupFunction<_CloudRegisterNative,
          _CloudRegisterDart>('rac_backend_cloud_register');
      final rc = fn();
      if (rc != RAC_SUCCESS &&
          rc != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.warning('rac_backend_cloud_register rc=$rc');
      }
      return rc;
    } catch (e) {
      _logger.warning(
        'rac_backend_cloud_register unavailable in this build: $e',
      );
      return null;
    }
  }

  /// Unregister the cloud engine. Returns the native rc, or null when the
  /// symbol is unavailable.
  int? unregisterCloud() {
    try {
      PlatformLoader.ensureCloudBackendLoaded();
      final fn = _lib.lookupFunction<_CloudRegisterNative,
          _CloudRegisterDart>('rac_backend_cloud_unregister');
      return fn();
    } catch (e) {
      _logger.debug('rac_backend_cloud_unregister unavailable: $e');
      return null;
    }
  }

  // --- Helpers -------------------------------------------------------------

  static Pointer<Uint8> _copyBytes(Uint8List bytes) {
    final ptr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
    }
    return ptr;
  }
}

// ============================================================================
// Single-process callback state.
//
// The C ABI holds ONE device-state vtable process-wide and a name-keyed
// custom-filter table; the Dart trampolines (top-level so they satisfy
// `Pointer.fromFunction`'s constant-tearoff requirement) resolve the active
// provider / predicate from this state. Mirrors the Swift/Kotlin "single
// installed provider + name→box map" lifetime model.
// ============================================================================

/// Host device-state callbacks consumed by the router's NETWORK / Battery
/// filters. Implementations must be reentrant (commons may call from multiple
/// request threads).
typedef HybridDeviceStateCallbacks = ({
  bool Function() isOnline,
  int Function() batteryPercent,
  bool Function() isThermalThrottled,
});

/// Predicate keyed by candidate model id. Returns true to keep the candidate.
typedef HybridCustomFilterCheck = bool Function(String modelId);

HybridDeviceStateCallbacks? _installedDeviceState;
final Map<String, HybridCustomFilterCheck> _customFilters =
    <String, HybridCustomFilterCheck>{};

int _deviceIsOnlineTrampoline(Pointer<Void> userData) {
  final p = _installedDeviceState;
  if (p == null) {
    return RAC_TRUE;
  }
  try {
    return p.isOnline() ? RAC_TRUE : RAC_FALSE;
  } catch (_) {
    return RAC_TRUE;
  }
}

int _deviceBatteryTrampoline(Pointer<Void> userData) {
  final p = _installedDeviceState;
  if (p == null) {
    return 100;
  }
  try {
    return p.batteryPercent();
  } catch (_) {
    return 100;
  }
}

int _deviceThermalTrampoline(Pointer<Void> userData) {
  final p = _installedDeviceState;
  if (p == null) {
    return RAC_FALSE;
  }
  try {
    return p.isThermalThrottled() ? RAC_TRUE : RAC_FALSE;
  } catch (_) {
    return RAC_FALSE;
  }
}

int _customFilterTrampoline(
  Pointer<_RacHybridRoutingContext> ctx,
  Pointer<Void> userData,
) {
  // Commons rewrites ctx.candidate_model_id to the candidate under evaluation,
  // but does NOT pass the predicate name — so the Dart trampoline cannot key by
  // name from the context alone. When exactly one predicate is registered (the
  // common case) dispatch to it; otherwise fail open (RAC_TRUE) so an
  // ambiguous registration never silently drops a candidate. Single-filter
  // policies are the documented usage across SDKs.
  if (_customFilters.length == 1) {
    final modelId = _readCandidateModelId(ctx);
    try {
      return _customFilters.values.first(modelId) ? RAC_TRUE : RAC_FALSE;
    } catch (_) {
      return RAC_TRUE;
    }
  }
  return RAC_TRUE;
}

String _readCandidateModelId(Pointer<_RacHybridRoutingContext> ctx) {
  if (ctx == nullptr) {
    return '';
  }
  final arr = ctx.ref.candidateModelId;
  final bytes = <int>[];
  for (var i = 0; i < 128; i++) {
    final b = arr[i];
    if (b == 0) {
      break;
    }
    bytes.add(b);
  }
  return String.fromCharCodes(bytes);
}
