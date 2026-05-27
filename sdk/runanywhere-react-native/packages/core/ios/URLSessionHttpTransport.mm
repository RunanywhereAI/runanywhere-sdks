// SPDX-License-Identifier: Apache-2.0
//
// URLSessionHttpTransport.mm (React Native wrapper)
//
// Per-SDK wrapper around the canonical implementation in
//   sdk/shared/ios/URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm
//
// flutter-core-012: this used to be a 462-line standalone copy of the
// implementation that drifted from the Flutter version (no host-session
// override, no `X-RAC-Range-Honored`, no `os_log`, no per-stream registry
// for `cancelAllStreams`). It has been collapsed into a thin shim that
// defines the RN-specific C entry-point and ObjC class prefixes and
// `#include`s the canonical body, so the Flutter and React Native plugins
// share one source of truth. The exported symbols
//   - rn_register_urlsession_transport
//   - rn_unregister_urlsession_transport
//   - rn_set_streaming_session       (newly exposed; not yet wired into
//                                     the RN Swift facade — additive)
//   - rn_cancel_all_streams          (newly exposed; not yet wired into
//                                     the RN Swift facade — additive)
// are referenced by the Swift façade at `URLSessionHttpTransport.swift`
// (register/unregister) and by `HybridRunAnywhereCore.cpp` (register).
//
// The path below is RELATIVE to this file on disk
// (sdk/runanywhere-react-native/packages/core/ios/) so that the compiler
// resolves it without needing a custom HEADER_SEARCH_PATHS entry. clang
// receives the realpath of this .mm at compile time, so relative-to-source
// resolution works for both Flutter and React Native consumers.

#define RAC_URLS_C_PREFIX    rn
#define RAC_URLS_OBJC_PREFIX RNRunAnywhere

#include "../../../../shared/ios/URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm"

#undef RAC_URLS_C_PREFIX
#undef RAC_URLS_OBJC_PREFIX
