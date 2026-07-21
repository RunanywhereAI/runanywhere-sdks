// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/connect.pb.dart' as connect_pb;
import 'package:runanywhere/generated/connect.pbenum.dart';
import 'package:runanywhere/generated/llm_service.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_connect.dart';
import 'package:uuid/uuid.dart';

/// A runtime host discovered on the local network.
final class ConnectHost {
  const ConnectHost({
    required this.id,
    required this.displayName,
    required this.protocolVersion,
  });

  final String id;
  final String displayName;
  final int protocolVersion;
}

/// The single language model selected and published by a connected host.
final class ConnectModel {
  const ConnectModel({
    required this.id,
    required this.displayName,
    required this.framework,
    required this.contextWindow,
    required this.supportsStreaming,
  });

  final String id;
  final String displayName;
  final String framework;
  final int contextWindow;
  final bool supportsStreaming;
}

enum ConnectStatus {
  idle,
  discovering,
  connecting,
  connected,
  disconnected,
  failed,
}

/// One observable snapshot for discovery, connection, model, and failure UI.
final class ConnectState {
  const ConnectState({
    this.status = ConnectStatus.idle,
    this.availableHosts = const <ConnectHost>[],
    this.connectingHost,
    this.activeHost,
    this.activeModel,
    this.lastDisconnectedHost,
    this.lastDisconnectedModel,
    this.message,
  });

  final ConnectStatus status;
  final List<ConnectHost> availableHosts;
  final ConnectHost? connectingHost;
  final ConnectHost? activeHost;
  final ConnectModel? activeModel;
  final ConnectHost? lastDisconnectedHost;
  final ConnectModel? lastDisconnectedModel;
  final String? message;

  bool get isConnected => status == ConnectStatus.connected;

  ConnectState copyWith({
    ConnectStatus? status,
    List<ConnectHost>? availableHosts,
    ConnectHost? connectingHost,
    bool clearConnectingHost = false,
    ConnectHost? activeHost,
    bool clearActiveHost = false,
    ConnectModel? activeModel,
    bool clearActiveModel = false,
    ConnectHost? lastDisconnectedHost,
    bool clearLastDisconnectedHost = false,
    ConnectModel? lastDisconnectedModel,
    bool clearLastDisconnectedModel = false,
    String? message,
    bool clearMessage = false,
  }) => ConnectState(
    status: status ?? this.status,
    availableHosts: availableHosts ?? this.availableHosts,
    connectingHost: clearConnectingHost
        ? null
        : connectingHost ?? this.connectingHost,
    activeHost: clearActiveHost ? null : activeHost ?? this.activeHost,
    activeModel: clearActiveModel ? null : activeModel ?? this.activeModel,
    lastDisconnectedHost: clearLastDisconnectedHost
        ? null
        : lastDisconnectedHost ?? this.lastDisconnectedHost,
    lastDisconnectedModel: clearLastDisconnectedModel
        ? null
        : lastDisconnectedModel ?? this.lastDisconnectedModel,
    message: clearMessage ? null : message ?? this.message,
  );
}

/// Flutter client for a RunAnywhere language model published by a host.
///
/// Discovery is opt-in. Commons owns role policy and handshake validation;
/// this SDK layer owns mDNS, framed TCP, heartbeat, and session observation.
final class ConnectSession {
  ConnectSession({String displayName = 'Flutter device'})
    : _displayName = displayName.trim().isEmpty
          ? 'Flutter device'
          : displayName.trim();

  static const int protocolVersion = 1;
  static const String _serviceName = '_runanywhere-connect._tcp.local';

  final String _displayName;
  final String _clientInstanceId = const Uuid().v4();
  final StreamController<ConnectState> _states = StreamController.broadcast();
  final Map<String, _ConnectEndpoint> _endpoints = <String, _ConnectEndpoint>{};
  final _ConnectSocket _socket = _ConnectSocket();

  ConnectState _state = const ConnectState();
  bool _browsing = false;
  bool _stopped = false;
  bool _discoveryResourcesHeld = false;
  String? _activeSessionId;

  ConnectState get state => _state;
  Stream<ConnectState> get states => _states.stream;

  Future<void> startBrowsing() async {
    _requireInitialized();
    final policy = DartBridgeConnect.platformPolicy(
      connect_pb.ConnectPlatformPolicyRequest(
        platform: ConnectPlatform.CONNECT_PLATFORM_FLUTTER,
      ),
    );
    if (policy.clientRole !=
        ConnectRoleAvailability.CONNECT_ROLE_AVAILABILITY_ENABLED) {
      throw SDKException.networkError(
        'Connect client support is not enabled for Flutter',
      );
    }
    if (_browsing) return;
    await _acquireDiscoveryResources();
    _browsing = true;
    _emit(
      _state.copyWith(
        status: _state.isConnected ? _state.status : ConnectStatus.discovering,
        clearMessage: true,
      ),
    );
    unawaited(_browseLoop());
  }

  void stopBrowsing() {
    _browsing = false;
    unawaited(_releaseDiscoveryResources());
    _endpoints.clear();
    _emit(
      _state.copyWith(
        status: _state.status == ConnectStatus.discovering
            ? ConnectStatus.idle
            : _state.status,
        availableHosts: const <ConnectHost>[],
      ),
    );
  }

  Future<void> connect(ConnectHost host) async {
    _requireInitialized();
    final endpoint = _endpoints[host.id];
    if (endpoint == null) {
      throw SDKException.networkError(
        'The selected host is no longer available',
      );
    }
    await _socket.close();
    _activeSessionId = null;
    _emit(
      _state.copyWith(
        status: ConnectStatus.connecting,
        connectingHost: host,
        clearActiveHost: true,
        clearActiveModel: true,
        clearMessage: true,
      ),
    );

    try {
      final hello = DartBridgeConnect.createClientHello(
        connect_pb.ConnectClientStartRequest(
          displayName: _displayName.length <= 128
              ? _displayName
              : _displayName.substring(0, 128),
          platform: ConnectPlatform.CONNECT_PLATFORM_FLUTTER,
          protocolVersion: protocolVersion,
        ),
      )..instanceId = _clientInstanceId;
      final response = await _socket.connect(endpoint, hello);
      final session = DartBridgeConnect.validateHost(response);
      if (session.state !=
              ConnectSessionState.CONNECT_SESSION_STATE_CONNECTED ||
          session.sessionId.isEmpty ||
          !session.hasHost() ||
          !session.hasModel() ||
          session.model.modelId.isEmpty) {
        throw SDKException.networkError(
          session.errorMessage.isEmpty
              ? 'The selected host could not provide a language model'
              : session.errorMessage,
        );
      }
      final connectedHost = ConnectHost(
        id: host.id,
        displayName: session.host.displayName.isEmpty
            ? host.displayName
            : session.host.displayName,
        protocolVersion: session.host.protocolVersion,
      );
      final connectedModel = ConnectModel(
        id: session.model.modelId,
        displayName: session.model.displayName,
        framework: session.model.framework,
        contextWindow: session.model.contextWindow,
        supportsStreaming: session.model.supportsStreaming,
      );
      _activeSessionId = session.sessionId;
      _emit(
        ConnectState(
          status: ConnectStatus.connected,
          availableHosts: _state.availableHosts,
          activeHost: connectedHost,
          activeModel: connectedModel,
        ),
      );
      _socket.startHeartbeat(session.sessionId, _handleDisconnect);
    } catch (error) {
      await _socket.close();
      _activeSessionId = null;
      _emit(
        _state.copyWith(
          status: ConnectStatus.failed,
          clearConnectingHost: true,
          clearActiveHost: true,
          clearActiveModel: true,
          message: _message(error, 'Unable to connect to the selected host'),
        ),
      );
      rethrow;
    }
  }

  Stream<LLMStreamEvent> generateStream(LLMGenerateRequest request) async* {
    final sessionId = _activeSessionId;
    final model = _state.activeModel;
    if (!_state.isConnected || sessionId == null || model == null) {
      throw SDKException.networkError(
        'Connect to a host before generating text',
      );
    }
    final requestId = request.requestId.isEmpty
        ? const Uuid().v4()
        : request.requestId;
    final generation = request.deepCopy()
      ..requestId = requestId
      ..modelId = model.id;
    try {
      yield* _socket.generate(
        connect_pb.ConnectInvocationRequest(
          sessionId: sessionId,
          requestId: requestId,
          generation: generation,
        ),
      );
    } catch (error) {
      _handleDisconnect(error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _socket.close();
    _activeSessionId = null;
    _emit(ConnectState(availableHosts: _state.availableHosts));
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _browsing = false;
    await _releaseDiscoveryResources();
    _endpoints.clear();
    await _socket.close();
    _activeSessionId = null;
    _emit(const ConnectState());
    await _states.close();
  }

  Future<void> _browseLoop() async {
    while (_browsing && !_stopped) {
      try {
        final endpoints = await _discoverOnce();
        if (!_browsing) return;
        _endpoints
          ..clear()
          ..addEntries(endpoints.map((value) => MapEntry(value.id, value)));
        final hosts = endpoints
            .map(
              (value) => ConnectHost(
                id: value.id,
                displayName: value.displayName,
                protocolVersion: protocolVersion,
              ),
            )
            .toList(growable: false);
        _emit(
          _state.copyWith(
            status: _state.status == ConnectStatus.failed
                ? ConnectStatus.discovering
                : _state.status,
            availableHosts: hosts,
            clearMessage: _state.status == ConnectStatus.failed,
          ),
        );
      } catch (error) {
        if (!_browsing) return;
        // Discovery is only needed to find another host. A transient mDNS
        // failure must not invalidate an already healthy TCP session; the
        // heartbeat remains authoritative for that connection.
        if (_state.isConnected) {
          await Future<void>.delayed(const Duration(seconds: 3));
          continue;
        }
        _emit(
          _state.copyWith(
            status: ConnectStatus.failed,
            message: _message(error, 'Unable to search the local network'),
          ),
        );
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<List<_ConnectEndpoint>> _discoverOnce() async {
    final client = MDnsClient();
    final endpoints = <String, _ConnectEndpoint>{};
    try {
      await client.start(onError: (Object error) {});
      final pointers = await client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceName),
            timeout: const Duration(seconds: 2),
          )
          .toList();
      for (final pointer in pointers) {
        final records = await client
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(pointer.domainName),
              timeout: const Duration(seconds: 2),
            )
            .toList();
        for (final record in records) {
          final target = record.target.trim().replaceFirst(RegExp(r'\.$'), '');
          if (target.isEmpty || record.port < 1 || record.port > 65535) {
            continue;
          }
          final addressRecords = await client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(record.target),
                timeout: const Duration(milliseconds: 750),
              )
              .toList();
          final resolvedHost = addressRecords.isEmpty
              ? target
              : addressRecords.first.address.address;
          endpoints[pointer.domainName] = _ConnectEndpoint(
            id: pointer.domainName,
            displayName: pointer.domainName
                .split('._runanywhere-connect')
                .first,
            host: resolvedHost,
            port: record.port,
          );
        }
      }
      return endpoints.values.toList()
        ..sort((left, right) => left.displayName.compareTo(right.displayName));
    } finally {
      client.stop();
    }
  }

  Future<void> _acquireDiscoveryResources() async {
    if (!Platform.isAndroid || _discoveryResourcesHeld) return;
    try {
      const channel = MethodChannel('runanywhere');
      final acquired =
          await channel.invokeMethod<bool>('connectAcquireMulticastLock') ??
          false;
      if (!acquired) {
        throw SDKException.networkError(
          'Unable to enable local-network discovery on Android',
        );
      }
      _discoveryResourcesHeld = true;
    } on SDKException {
      rethrow;
    } catch (error) {
      throw SDKException.networkError(
        'Unable to enable local-network discovery on Android: $error',
      );
    }
  }

  Future<void> _releaseDiscoveryResources() async {
    if (!Platform.isAndroid || !_discoveryResourcesHeld) return;
    _discoveryResourcesHeld = false;
    try {
      const channel = MethodChannel('runanywhere');
      await channel.invokeMethod<void>('connectReleaseMulticastLock');
    } catch (_) {
      // The Flutter engine may already be detaching; Android releases the lock
      // from the plugin lifecycle as a final safety net.
    }
  }

  void _handleDisconnect(Object error) {
    if (!_state.isConnected) return;
    final previous = _state;
    _activeSessionId = null;
    unawaited(_socket.close());
    final hostName = previous.activeHost?.displayName ?? 'the host';
    _emit(
      previous.copyWith(
        status: ConnectStatus.disconnected,
        clearConnectingHost: true,
        clearActiveHost: true,
        clearActiveModel: true,
        lastDisconnectedHost: previous.activeHost,
        lastDisconnectedModel: previous.activeModel,
        message:
            'Connection to $hostName ended. The host may have stopped or left the network.',
      ),
    );
  }

  void _emit(ConnectState value) {
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }

  void _requireInitialized() {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized('RunAnywhere Connect');
    }
  }

  String _message(Object error, String fallback) {
    if (error is SDKException && error.message.isNotEmpty) return error.message;
    final value = error.toString().trim();
    return value.isEmpty ? fallback : value;
  }
}

final class _ConnectEndpoint {
  const _ConnectEndpoint({
    required this.id,
    required this.displayName,
    required this.host,
    required this.port,
  });

  final String id;
  final String displayName;
  final String host;
  final int port;
}

final class _ConnectSocket {
  Socket? _socket;
  StreamIterator<Uint8List>? _iterator;
  final List<int> _buffer = <int>[];
  Timer? _heartbeat;
  bool _operationActive = false;
  bool _closed = true;

  Future<connect_pb.ConnectHandshakeResponse> connect(
    _ConnectEndpoint endpoint,
    connect_pb.ConnectClientHello hello,
  ) async {
    await close();
    try {
      // Ownership is transferred to this transport and released by close().
      // ignore: close_sinks
      final socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: const Duration(seconds: 5),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      _iterator = StreamIterator<Uint8List>(socket);
      _closed = false;
      _writeFrame(hello.writeToBuffer());
      return connect_pb.ConnectHandshakeResponse.fromBuffer(
        await _readFrame().timeout(const Duration(seconds: 5)),
      );
    } catch (error) {
      await close();
      throw SDKException.networkError(
        'Unable to connect to ${endpoint.displayName}: $error',
      );
    }
  }

  void startHeartbeat(String sessionId, void Function(Object) onDisconnected) {
    _heartbeat?.cancel();
    var sequence = 0;
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_closed || _operationActive) return;
      unawaited(() async {
        _operationActive = true;
        try {
          sequence += 1;
          _writeFrame(
            connect_pb.ConnectClientFrame(
              heartbeat: connect_pb.ConnectHeartbeatRequest(
                sessionId: sessionId,
                sequence: Int64(sequence),
              ),
            ).writeToBuffer(),
          );
          final frame = connect_pb.ConnectHostFrame.fromBuffer(
            await _readFrame().timeout(const Duration(seconds: 2)),
          );
          if (!frame.hasHeartbeat() ||
              frame.heartbeat.sessionId != sessionId ||
              frame.heartbeat.sequence.toInt() != sequence) {
            throw SDKException.networkError(
              'The Connect host returned an invalid heartbeat',
            );
          }
        } catch (error) {
          onDisconnected(error);
        } finally {
          _operationActive = false;
        }
      }());
    });
  }

  Stream<LLMStreamEvent> generate(
    connect_pb.ConnectInvocationRequest request,
  ) async* {
    if (_closed || _socket == null) {
      throw SDKException.networkError(
        'The selected host is no longer connected',
      );
    }
    if (_operationActive) {
      throw SDKException.networkError(
        'Another Connect operation is already running',
      );
    }
    _operationActive = true;
    try {
      _writeFrame(
        connect_pb.ConnectClientFrame(invocation: request).writeToBuffer(),
      );
      while (true) {
        final frame = connect_pb.ConnectHostFrame.fromBuffer(
          await _readFrame(),
        );
        if (!frame.hasInvocationEvent() ||
            frame.invocationEvent.requestId != request.requestId ||
            !frame.invocationEvent.hasEvent()) {
          throw SDKException.networkError(
            'The Connect host returned an invalid response',
          );
        }
        final event = frame.invocationEvent.event;
        yield event;
        if (event.isFinal) break;
      }
    } finally {
      _operationActive = false;
    }
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _closed = true;
    _operationActive = false;
    final iterator = _iterator;
    _iterator = null;
    final socket = _socket;
    _socket = null;
    _buffer.clear();
    await iterator?.cancel();
    await socket?.close();
  }

  void _writeFrame(List<int> payload) {
    if (payload.isEmpty || payload.length > 4 * 1024 * 1024) {
      throw SDKException.networkError('Connect frame size is invalid');
    }
    final header = ByteData(4)..setUint32(0, payload.length, Endian.big);
    _socket
      ?..add(header.buffer.asUint8List())
      ..add(payload);
  }

  Future<Uint8List> _readFrame() async {
    while (_buffer.length < 4) {
      await _readChunk();
    }
    final header = Uint8List.fromList(_buffer.sublist(0, 4));
    final length = ByteData.sublistView(header).getUint32(0, Endian.big);
    if (length < 1 || length > 4 * 1024 * 1024) {
      throw SDKException.networkError(
        'The Connect host returned an invalid frame size',
      );
    }
    while (_buffer.length < 4 + length) {
      await _readChunk();
    }
    final payload = Uint8List.fromList(_buffer.sublist(4, 4 + length));
    _buffer.removeRange(0, 4 + length);
    return payload;
  }

  Future<void> _readChunk() async {
    final iterator = _iterator;
    if (iterator == null || !await iterator.moveNext()) {
      throw const SocketException('The connection to the host ended');
    }
    _buffer.addAll(iterator.current);
  }
}
