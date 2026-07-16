import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';

/// App-scoped, thin observable owner for the SDK Connect session.
final class ConnectService extends ChangeNotifier {
  ConnectService._() {
    _subscription = session.states.listen((value) {
      _state = value;
      notifyListeners();
    });
  }

  static final ConnectService shared = ConnectService._();

  final ConnectSession session = ConnectSession();
  late final StreamSubscription<ConnectState> _subscription;
  ConnectState _state = const ConnectState();

  ConnectState get state => _state;

  Future<void> findHosts() => session.startBrowsing();
  void stopFindingHosts() => session.stopBrowsing();
  Future<void> connect(ConnectHost host) => session.connect(host);
  Future<void> disconnect() => session.disconnect();

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(session.stop());
    super.dispose();
  }
}
