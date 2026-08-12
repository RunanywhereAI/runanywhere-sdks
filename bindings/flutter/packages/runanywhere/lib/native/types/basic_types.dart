// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';


/// =============================================================================
/// RunAnywhere Commons FFI Type Definitions
///
/// Dart FFI types matching the C API defined in rac_*.h headers
/// from runanywhere-commons library.
/// =============================================================================

// =============================================================================
// Basic Types (from rac_types.h)
// =============================================================================

/// Opaque handle for internal objects (rac_handle_t)
typedef RacHandle = Pointer<Void>;

/// Result type for all RAC functions (rac_result_t)
/// 0 = success, negative = error
typedef RacResult = Int32;

/// RAC boolean values
const int RAC_TRUE = 1;
const int RAC_FALSE = 0;

/// RAC success value
const int RAC_SUCCESS = 0;

// =============================================================================
// Result Codes (from rac_error.h)
//
// The table moved to generated/ra_result_codes.dart as `RacResultCodes`,
// emitted from idl/errors.proto. It had grown to 125 hand-copied integers plus a
// 29-case message switch; the numbers and the messages are both derivable, so
// neither is written here now.
// =============================================================================

// =============================================================================
// Log Levels (from rac_types.h)
// =============================================================================

/// Log level for the logging callback (rac_log_level_t), as the raw C-ABI
/// integers the native layer expects.
///
/// These mirror the generated `LogLevel` proto enum value-for-value
/// (`LOG_LEVEL_TRACE = 0 … LOG_LEVEL_FATAL = 5`, see `generated/logging.pbenum
/// .dart`), which is itself aligned with `enum rac_log_level` in
/// `include/rac/core/rac_types.h`. They are kept as `const int` literals (not
/// `LogLevel.*.value`) because FFI call sites use them as `switch` `case`
/// labels, which Dart requires to be compile-time constants.
abstract class RacLogLevel {
  static const int trace = 0;
  static const int debug = 1;
  static const int info = 2;
  static const int warning = 3;
  static const int error = 4;
  static const int fatal = 5;
}
