// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';


// =============================================================================
// Memory Management (from rac_types.h)
// =============================================================================

/// void rac_free(void* ptr)
typedef RacFreeNative = Void Function(Pointer<Void> ptr);
typedef RacFreeDart = void Function(Pointer<Void> ptr);

/// void* rac_alloc(size_t size)
typedef RacAllocNative = Pointer<Void> Function(IntPtr size);
typedef RacAllocDart = Pointer<Void> Function(int size);

/// char* rac_strdup(const char* str)
typedef RacStrdupNative = Pointer<Utf8> Function(Pointer<Utf8> str);
typedef RacStrdupDart = Pointer<Utf8> Function(Pointer<Utf8> str);

// =============================================================================
// Error API (from rac_error.h)
// =============================================================================

/// const char* rac_error_message(rac_result_t error_code)
typedef RacErrorMessageNative = Pointer<Utf8> Function(Int32 errorCode);
typedef RacErrorMessageDart = Pointer<Utf8> Function(int errorCode);

/// const char* rac_error_get_details(void)
typedef RacErrorGetDetailsNative = Pointer<Utf8> Function();
typedef RacErrorGetDetailsDart = Pointer<Utf8> Function();

/// void rac_error_set_details(const char* details)
typedef RacErrorSetDetailsNative = Void Function(Pointer<Utf8> details);
typedef RacErrorSetDetailsDart = void Function(Pointer<Utf8> details);

/// void rac_error_clear_details(void)
typedef RacErrorClearDetailsNative = Void Function();
typedef RacErrorClearDetailsDart = void Function();

// =============================================================================
// Platform Adapter Callbacks (from rac_platform_adapter.h)
// =============================================================================

/// File exists callback: rac_bool_t (*file_exists)(const char* path, void* user_data)
typedef RacFileExistsCallbackNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Void> userData,
);

/// File read callback: rac_result_t (*file_read)(const char* path, void** out_data, size_t* out_size, void* user_data)
typedef RacFileReadCallbackNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Pointer<Void>> outData,
  Pointer<IntPtr> outSize,
  Pointer<Void> userData,
);

/// File write callback: rac_result_t (*file_write)(const char* path, const void* data, size_t size, void* user_data)
typedef RacFileWriteCallbackNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Void> data,
  IntPtr size,
  Pointer<Void> userData,
);

/// File delete callback: rac_result_t (*file_delete)(const char* path, void* user_data)
typedef RacFileDeleteCallbackNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Void> userData,
);

/// Secure get callback: rac_result_t (*secure_get)(const char* key, char** out_value, void* user_data)
typedef RacSecureGetCallbackNative = Int32 Function(
  Pointer<Utf8> key,
  Pointer<Pointer<Utf8>> outValue,
  Pointer<Void> userData,
);

/// Secure set callback: rac_result_t (*secure_set)(const char* key, const char* value, void* user_data)
typedef RacSecureSetCallbackNative = Int32 Function(
  Pointer<Utf8> key,
  Pointer<Utf8> value,
  Pointer<Void> userData,
);

/// Secure delete callback: rac_result_t (*secure_delete)(const char* key, void* user_data)
typedef RacSecureDeleteCallbackNative = Int32 Function(
  Pointer<Utf8> key,
  Pointer<Void> userData,
);

/// Log callback: void (*log)(rac_log_level_t level, const char* category, const char* message, void* user_data)
typedef RacLogCallbackNative = Void Function(
  Int32 level,
  Pointer<Utf8> category,
  Pointer<Utf8> message,
  Pointer<Void> userData,
);

/// Track error callback: void (*track_error)(const char* error_json, void* user_data)
typedef RacTrackErrorCallbackNative = Void Function(
  Pointer<Utf8> errorJson,
  Pointer<Void> userData,
);

/// Now ms callback: int64_t (*now_ms)(void* user_data)
typedef RacNowMsCallbackNative = Int64 Function(Pointer<Void> userData);

/// Get memory info callback: rac_result_t (*get_memory_info)(rac_memory_info_t* out_info, void* user_data)
typedef RacGetMemoryInfoCallbackNative = Int32 Function(
  Pointer<Void> outInfo,
  Pointer<Void> userData,
);

/// HTTP progress callback: void (*progress)(int64_t bytes_downloaded, int64_t total_bytes, void* callback_user_data)
typedef RacHttpProgressCallbackNative = Void Function(
  Int64 bytesDownloaded,
  Int64 totalBytes,
  Pointer<Void> callbackUserData,
);

/// HTTP complete callback: void (*complete)(rac_result_t result, const char* downloaded_path, void* callback_user_data)
typedef RacHttpCompleteCallbackNative = Void Function(
  Int32 result,
  Pointer<Utf8> downloadedPath,
  Pointer<Void> callbackUserData,
);

/// HTTP download callback: rac_result_t (*http_download)(const char* url, const char* destination_path,
///     rac_http_progress_callback_fn progress_callback, rac_http_complete_callback_fn complete_callback,
///     void* callback_user_data, char** out_task_id, void* user_data)
typedef RacHttpDownloadCallbackNative = Int32 Function(
  Pointer<Utf8> url,
  Pointer<Utf8> destinationPath,
  Pointer<NativeFunction<RacHttpProgressCallbackNative>> progressCallback,
  Pointer<NativeFunction<RacHttpCompleteCallbackNative>> completeCallback,
  Pointer<Void> callbackUserData,
  Pointer<Pointer<Utf8>> outTaskId,
  Pointer<Void> userData,
);

/// HTTP download cancel callback: rac_result_t (*http_download_cancel)(const char* task_id, void* user_data)
typedef RacHttpDownloadCancelCallbackNative = Int32 Function(
  Pointer<Utf8> taskId,
  Pointer<Void> userData,
);

// =============================================================================
// Structs (using FFI Struct for native memory layout)
// =============================================================================

/// Platform adapter struct matching rac_platform_adapter_t
/// Note: This is a complex struct - for simplicity we use Pointer<Void> in FFI calls
/// and manage the struct manually in Dart
base class RacPlatformAdapterStruct extends Struct {
  external Pointer<NativeFunction<RacFileExistsCallbackNative>> fileExists;
  external Pointer<NativeFunction<RacFileReadCallbackNative>> fileRead;
  external Pointer<NativeFunction<RacFileWriteCallbackNative>> fileWrite;
  external Pointer<NativeFunction<RacFileDeleteCallbackNative>> fileDelete;
  external Pointer<NativeFunction<RacSecureGetCallbackNative>> secureGet;
  external Pointer<NativeFunction<RacSecureSetCallbackNative>> secureSet;
  external Pointer<NativeFunction<RacSecureDeleteCallbackNative>> secureDelete;
  external Pointer<NativeFunction<RacLogCallbackNative>> log;
  external Pointer<NativeFunction<RacTrackErrorCallbackNative>> trackError;
  external Pointer<NativeFunction<RacNowMsCallbackNative>> nowMs;
  external Pointer<NativeFunction<RacGetMemoryInfoCallbackNative>>
      getMemoryInfo;
  external Pointer<Void> httpDownload;
  external Pointer<Void> httpDownloadCancel;
  external Pointer<Void> extractArchive;
  external Pointer<Void> userData;
}

/// Memory info struct matching rac_memory_info_t
base class RacMemoryInfoStruct extends Struct {
  @Uint64()
  external int totalBytes;

  @Uint64()
  external int availableBytes;

  @Uint64()
  external int usedBytes;
}

/// Version info struct matching rac_version_t
base class RacVersionStruct extends Struct {
  @Uint16()
  external int major;

  @Uint16()
  external int minor;

  @Uint16()
  external int patch;

  external Pointer<Utf8> string;
}
