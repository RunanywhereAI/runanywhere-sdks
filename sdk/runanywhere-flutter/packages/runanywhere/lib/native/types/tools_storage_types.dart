// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';

// File Manager Types (from rac_file_manager.h)
// =============================================================================

/// Callback: create_directory(path, recursive, user_data) -> rac_result_t
typedef RacFmCreateDirectoryNative =
    Int32 Function(Pointer<Utf8>, Int32, Pointer<Void>);

/// Callback: delete_path(path, recursive, user_data) -> rac_result_t
typedef RacFmDeletePathNative =
    Int32 Function(Pointer<Utf8>, Int32, Pointer<Void>);

/// Callback: list_directory(path, out_entries, out_count, user_data) -> rac_result_t
typedef RacFmListDirectoryNative =
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Pointer<Pointer<Utf8>>>,
      Pointer<Size>,
      Pointer<Void>,
    );

/// Callback: free_entries(entries, count, user_data)
typedef RacFmFreeEntriesNative =
    Void Function(Pointer<Pointer<Utf8>>, Size, Pointer<Void>);

/// Callback: path_exists(path, out_is_directory, user_data) -> rac_bool_t
typedef RacFmPathExistsNative =
    Int32 Function(Pointer<Utf8>, Pointer<Int32>, Pointer<Void>);

/// Callback: get_file_size(path, user_data) -> int64_t
typedef RacFmGetFileSizeNative = Int64 Function(Pointer<Utf8>, Pointer<Void>);

/// Callback: get_available_space(user_data) -> int64_t
typedef RacFmGetAvailableSpaceNative = Int64 Function(Pointer<Void>);

/// Callback: get_total_space(user_data) -> int64_t
typedef RacFmGetTotalSpaceNative = Int64 Function(Pointer<Void>);

/// File callbacks struct matching rac_file_callbacks_t
final class RacFileCallbacksStruct extends Struct {
  external Pointer<NativeFunction<RacFmCreateDirectoryNative>> createDirectory;
  external Pointer<NativeFunction<RacFmDeletePathNative>> deletePath;
  external Pointer<NativeFunction<RacFmListDirectoryNative>> listDirectory;
  external Pointer<NativeFunction<RacFmFreeEntriesNative>> freeEntries;
  external Pointer<NativeFunction<RacFmPathExistsNative>> pathExists;
  external Pointer<NativeFunction<RacFmGetFileSizeNative>> getFileSize;
  external Pointer<NativeFunction<RacFmGetAvailableSpaceNative>>
  getAvailableSpace;
  external Pointer<NativeFunction<RacFmGetTotalSpaceNative>> getTotalSpace;
  external Pointer<Void> userData;
}

/// Storage info struct matching rac_file_manager_storage_info_t
final class RacFileManagerStorageInfoStruct extends Struct {
  @Int64()
  external int deviceTotal;
  @Int64()
  external int deviceFree;
  @Int64()
  external int modelsSize;
  @Int64()
  external int cacheSize;
  @Int64()
  external int tempSize;
  @Int64()
  external int totalAppSize;
}

/// Storage availability struct matching rac_storage_availability_t
final class RacStorageAvailabilityStruct extends Struct {
  @Int32()
  external int isAvailable;
  @Int64()
  external int requiredSpace;
  @Int64()
  external int availableSpace;
  @Int32()
  external int hasWarning;
  external Pointer<Utf8> recommendation;
}
