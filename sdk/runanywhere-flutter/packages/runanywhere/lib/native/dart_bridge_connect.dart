// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi' as ffi;

import 'package:protobuf/protobuf.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/connect.pb.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/platform_loader.dart';

typedef _ConnectProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef _ConnectProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

/// Thin protobuf facade over the Commons-owned Connect policy and handshake.
abstract final class DartBridgeConnect {
  static final ffi.DynamicLibrary _library = PlatformLoader.loadCommons();

  static ConnectPlatformPolicy platformPolicy(
    ConnectPlatformPolicyRequest request,
  ) => _call(
    request: request,
    symbol: 'rac_connect_get_platform_policy_proto',
    decode: ConnectPlatformPolicy.fromBuffer,
  );

  static ConnectClientHello createClientHello(
    ConnectClientStartRequest request,
  ) => _call(
    request: request,
    symbol: 'rac_connect_client_create_hello_proto',
    decode: ConnectClientHello.fromBuffer,
  );

  static ConnectClientSessionState validateHost(
    ConnectHandshakeResponse response,
  ) => _call(
    request: response,
    symbol: 'rac_connect_client_validate_host_proto',
    decode: ConnectClientSessionState.fromBuffer,
  );

  static T _call<T extends GeneratedMessage>({
    required GeneratedMessage request,
    required String symbol,
    required T Function(List<int>) decode,
  }) {
    final function = _library
        .lookupFunction<_ConnectProtoNative, _ConnectProtoDart>(symbol);
    return DartBridgeProtoUtils.callRequest(
      request: request,
      invoke: function,
      decode: decode,
      symbol: symbol,
    );
  }
}
