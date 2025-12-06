/// Native FFI utilities for RunAnywhere backends.
///
/// This module provides the low-level FFI bindings to runanywhere-core.
/// It is used internally by backend modules (ONNX, llama.cpp, etc.).
///
/// ## Components
///
/// - [NativeBackend]: Main FFI wrapper for the C API
/// - [PlatformLoader]: Platform-specific library loading
/// - FFI type definitions for C interop
library runanywhere_native;

export 'native_backend.dart';
export 'platform_loader.dart';
export 'ffi_types.dart';
