// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/native/types/basic_types.dart';

// =============================================================================
// Core API Function Signatures (from rac_core.h)
// =============================================================================

/// rac_result_t rac_init(const rac_config_t* config)
typedef RacInitNative = Int32 Function(Pointer<Void> config);
typedef RacInitDart = int Function(Pointer<Void> config);

/// void rac_shutdown(void)
typedef RacShutdownNative = Void Function();
typedef RacShutdownDart = void Function();

/// rac_bool_t rac_is_initialized(void)
typedef RacIsInitializedNative = Int32 Function();
typedef RacIsInitializedDart = int Function();

/// rac_result_t rac_configure_logging(rac_environment_t environment)
typedef RacConfigureLoggingNative = Int32 Function(Int32 environment);
typedef RacConfigureLoggingDart = int Function(int environment);

// =============================================================================
// Module Registration API (from rac_core.h)
// =============================================================================

/// rac_result_t rac_module_register(const rac_module_info_t* info)
typedef RacModuleRegisterNative = Int32 Function(Pointer<Void> info);
typedef RacModuleRegisterDart = int Function(Pointer<Void> info);

/// rac_result_t rac_module_unregister(const char* module_id)
typedef RacModuleUnregisterNative = Int32 Function(Pointer<Utf8> moduleId);
typedef RacModuleUnregisterDart = int Function(Pointer<Utf8> moduleId);

/// rac_result_t rac_module_list(const rac_module_info_t** out_modules, size_t* out_count)
typedef RacModuleListNative = Int32 Function(
  Pointer<Pointer<Void>> outModules,
  Pointer<IntPtr> outCount,
);
typedef RacModuleListDart = int Function(
  Pointer<Pointer<Void>> outModules,
  Pointer<IntPtr> outCount,
);

// =============================================================================
// v3.0.0 (C1): legacy rac_service_{register_provider,create,...} typedefs
// DELETED. New code uses rac_plugin_{register,route,list} via
// RacBindings in lib/core/native/rac_native.dart.
// =============================================================================

// =============================================================================
// LLM API Function Signatures (from rac_llm_llamacpp.h)
// =============================================================================

/// rac_result_t rac_backend_llamacpp_register(void)
typedef RacBackendLlamacppRegisterNative = Int32 Function();
typedef RacBackendLlamacppRegisterDart = int Function();

/// rac_result_t rac_backend_llamacpp_unregister(void)
typedef RacBackendLlamacppUnregisterNative = Int32 Function();
typedef RacBackendLlamacppUnregisterDart = int Function();

/// rac_result_t rac_backend_llamacpp_vlm_register(void)
typedef RacBackendLlamacppVlmRegisterNative = Int32 Function();
typedef RacBackendLlamacppVlmRegisterDart = int Function();

/// rac_result_t rac_backend_llamacpp_vlm_unregister(void)
typedef RacBackendLlamacppVlmUnregisterNative = Int32 Function();
typedef RacBackendLlamacppVlmUnregisterDart = int Function();

// =============================================================================
// LLM Component API Function Signatures (from rac_llm_component.h)
// =============================================================================

/// rac_result_t rac_llm_component_create(rac_handle_t* out_handle)
typedef RacLlmComponentCreateNative = Int32 Function(
  Pointer<RacHandle> outHandle,
);
typedef RacLlmComponentCreateDart = int Function(
  Pointer<RacHandle> outHandle,
);

/// rac_result_t rac_llm_component_load_model(rac_handle_t handle, const char* model_path, const char* model_id, const char* model_name)
typedef RacLlmComponentLoadModelNative = Int32 Function(
  RacHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> modelId,
  Pointer<Utf8> modelName,
);
typedef RacLlmComponentLoadModelDart = int Function(
  RacHandle handle,
  Pointer<Utf8> modelPath,
  Pointer<Utf8> modelId,
  Pointer<Utf8> modelName,
);

/// rac_bool_t rac_llm_component_is_loaded(rac_handle_t handle)
typedef RacLlmComponentIsLoadedNative = Int32 Function(RacHandle handle);
typedef RacLlmComponentIsLoadedDart = int Function(RacHandle handle);

/// const char* rac_llm_component_get_model_id(rac_handle_t handle)
typedef RacLlmComponentGetModelIdNative = Pointer<Utf8> Function(
    RacHandle handle);
typedef RacLlmComponentGetModelIdDart = Pointer<Utf8> Function(RacHandle handle);

/// rac_result_t rac_llm_component_generate(rac_handle_t handle, const char* prompt, const rac_llm_options_t* options, rac_llm_result_t* out_result)
typedef RacLlmComponentGenerateNative = Int32 Function(
  RacHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Void> options,
  Pointer<Void> outResult,
);
typedef RacLlmComponentGenerateDart = int Function(
  RacHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Void> options,
  Pointer<Void> outResult,
);

/// LLM streaming token callback signature
/// rac_bool_t (*rac_llm_component_token_callback_fn)(const char* token, void* user_data)
typedef RacLlmComponentTokenCallbackNative = Int32 Function(
  Pointer<Utf8> token,
  Pointer<Void> userData,
);

/// LLM streaming complete callback signature
typedef RacLlmComponentCompleteCallbackNative = Void Function(
  Pointer<Void> result,
  Pointer<Void> userData,
);

/// LLM streaming error callback signature
typedef RacLlmComponentErrorCallbackNative = Void Function(
  Int32 errorCode,
  Pointer<Utf8> errorMessage,
  Pointer<Void> userData,
);

/// rac_result_t rac_llm_component_generate_stream(...)
typedef RacLlmComponentGenerateStreamNative = Int32 Function(
  RacHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Void> options,
  Pointer<NativeFunction<RacLlmComponentTokenCallbackNative>> tokenCallback,
  Pointer<NativeFunction<RacLlmComponentCompleteCallbackNative>>
      completeCallback,
  Pointer<NativeFunction<RacLlmComponentErrorCallbackNative>> errorCallback,
  Pointer<Void> userData,
);
typedef RacLlmComponentGenerateStreamDart = int Function(
  RacHandle handle,
  Pointer<Utf8> prompt,
  Pointer<Void> options,
  Pointer<NativeFunction<RacLlmComponentTokenCallbackNative>> tokenCallback,
  Pointer<NativeFunction<RacLlmComponentCompleteCallbackNative>>
      completeCallback,
  Pointer<NativeFunction<RacLlmComponentErrorCallbackNative>> errorCallback,
  Pointer<Void> userData,
);

/// rac_result_t rac_llm_component_cancel(rac_handle_t handle)
typedef RacLlmComponentCancelNative = Int32 Function(RacHandle handle);
typedef RacLlmComponentCancelDart = int Function(RacHandle handle);

/// rac_result_t rac_llm_component_unload(rac_handle_t handle)
typedef RacLlmComponentUnloadNative = Int32 Function(RacHandle handle);
typedef RacLlmComponentUnloadDart = int Function(RacHandle handle);

/// rac_result_t rac_llm_component_cleanup(rac_handle_t handle)
typedef RacLlmComponentCleanupNative = Int32 Function(RacHandle handle);
typedef RacLlmComponentCleanupDart = int Function(RacHandle handle);

/// void rac_llm_component_destroy(rac_handle_t handle)
typedef RacLlmComponentDestroyNative = Void Function(RacHandle handle);
typedef RacLlmComponentDestroyDart = void Function(RacHandle handle);

// Legacy aliases for backward compatibility (unused - remove after migration)
typedef RacLlmStreamCallbackNative = RacLlmComponentTokenCallbackNative;
