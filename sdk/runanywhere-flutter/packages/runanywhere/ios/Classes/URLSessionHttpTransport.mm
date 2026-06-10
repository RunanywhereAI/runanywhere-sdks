// SPDX-License-Identifier: Apache-2.0
//
// URLSessionHttpTransport.mm (Flutter wrapper)
//
// Per-SDK wrapper around the canonical implementation in
//   sdk/shared/ios/URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm
//
// flutter-core-012: this used to be a 686-line standalone copy of the
// implementation. It has been collapsed into a thin shim that defines the
// Flutter-specific C entry-point and ObjC class prefixes and `#include`s the
// canonical body, so the Flutter and React Native plugins share one source
// of truth. The exported symbols
//   - ra_flutter_register_urlsession_transport
//   - ra_flutter_unregister_urlsession_transport
//   - ra_flutter_set_streaming_session
//   - ra_flutter_cancel_all_streams
// are unchanged; the Swift façade at `URLSessionHttpTransport.swift`
// continues to reference them via `@_silgen_name`.
//
// The path below is RELATIVE to this file on disk
// (sdk/runanywhere-flutter/packages/runanywhere/ios/Classes/) so that the
// compiler resolves it without needing a custom HEADER_SEARCH_PATHS entry.
// CocoaPods can mount this pod through a symlink (e.g. Flutter's
// `.symlinks/plugins/runanywhere`) but clang receives the realpath of the
// .mm at compile time, so relative-to-source resolution Just Works for
// both Flutter and React Native consumers.

#define RAC_URLS_C_PREFIX    ra_flutter
#define RAC_URLS_OBJC_PREFIX RAFlutter

#include "../../../../../shared/ios/URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm"

#undef RAC_URLS_C_PREFIX
#undef RAC_URLS_OBJC_PREFIX
