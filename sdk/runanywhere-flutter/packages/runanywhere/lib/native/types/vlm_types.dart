// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';


// =============================================================================
// VLM API Types (from rac_vlm_types.h)
// =============================================================================

/// VLM image format enumeration
abstract class RacVlmImageFormat {
  static const int filePath = 0; // RAC_VLM_IMAGE_FORMAT_FILE_PATH
  static const int rgbPixels = 1; // RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
  static const int base64 = 2; // RAC_VLM_IMAGE_FORMAT_BASE64
}

/// VLM image input structure (matches rac_vlm_image_t)
base class RacVlmImageStruct extends Struct {
  @Int32()
  external int format; // rac_vlm_image_format_t

  external Pointer<Utf8> filePath; // const char* file_path
  external Pointer<Uint8> pixelData; // const uint8_t* pixel_data
  external Pointer<Utf8> base64Data; // const char* base64_data

  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @IntPtr()
  external int dataSize; // size_t
}

/// VLM generation options (matches rac_vlm_options_t)
base class RacVlmOptionsStruct extends Struct {
  @Int32()
  external int maxTokens;

  @Float()
  external double temperature;

  @Float()
  external double topP;

  external Pointer<Pointer<Utf8>> stopSequences;

  @IntPtr()
  external int numStopSequences;

  @Int32()
  external int streamingEnabled; // rac_bool_t

  external Pointer<Utf8> systemPrompt;

  @Int32()
  external int maxImageSize;

  @Int32()
  external int nThreads;

  @Int32()
  external int useGpu; // rac_bool_t

  @Int32()
  external int modelFamily; // rac_vlm_model_family_t (0 = AUTO)

  external Pointer<Void> customChatTemplate; // const rac_vlm_chat_template_t*

  external Pointer<Utf8> imageMarkerOverride; // const char*
}

/// VLM generation result (matches rac_vlm_result_t)
base class RacVlmResultStruct extends Struct {
  external Pointer<Utf8> text;

  @Int32()
  external int promptTokens;

  @Int32()
  external int imageTokens;

  @Int32()
  external int completionTokens;

  @Int32()
  external int totalTokens;

  @Int64()
  external int timeToFirstTokenMs;

  @Int64()
  external int imageEncodeTimeMs;

  @Int64()
  external int totalTimeMs;

  @Float()
  external double tokensPerSecond;
}

/// VLM component token callback signature
/// rac_bool_t (*rac_vlm_component_token_callback_fn)(const char* token, void* user_data)
typedef RacVlmComponentTokenCallbackNative = Int32 Function(
  Pointer<Utf8> token,
  Pointer<Void> userData,
);

/// VLM component completion callback signature
/// void (*rac_vlm_component_complete_callback_fn)(const rac_vlm_result_t* result, void* user_data)
typedef RacVlmComponentCompleteCallbackNative = Void Function(
  Pointer<RacVlmResultStruct> result,
  Pointer<Void> userData,
);

/// VLM component error callback signature
/// void (*rac_vlm_component_error_callback_fn)(rac_result_t error_code, const char* error_message, void* user_data)
typedef RacVlmComponentErrorCallbackNative = Void Function(
  Int32 errorCode,
  Pointer<Utf8> errorMessage,
  Pointer<Void> userData,
);
