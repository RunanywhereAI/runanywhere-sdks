import 'dart:async';

import 'package:runanywhere/public/events/sdk_event.dart';

/// Central event bus for SDK-wide event distribution
/// Thread-safe event bus using Dart Streams
class EventBus {
  /// Shared instance - thread-safe singleton
  static final EventBus shared = EventBus._();

  EventBus._();

  // Event controllers for each event type
  final _initializationController =
      StreamController<SDKInitializationEvent>.broadcast();
  final _configurationController =
      StreamController<SDKConfigurationEvent>.broadcast();
  final _generationController =
      StreamController<SDKGenerationEvent>.broadcast();
  final _modelController = StreamController<SDKModelEvent>.broadcast();
  final _voiceController = StreamController<SDKVoiceEvent>.broadcast();
  final _storageController = StreamController<SDKStorageEvent>.broadcast();
  final _deviceController = StreamController<SDKDeviceEvent>.broadcast();
  final _allEventsController = StreamController<SDKEvent>.broadcast();

  /// Public streams for subscribing to events
  Stream<SDKInitializationEvent> get initializationEvents =>
      _initializationController.stream;

  Stream<SDKConfigurationEvent> get configurationEvents =>
      _configurationController.stream;

  Stream<SDKGenerationEvent> get generationEvents =>
      _generationController.stream;

  Stream<SDKModelEvent> get modelEvents => _modelController.stream;

  Stream<SDKVoiceEvent> get voiceEvents => _voiceController.stream;

  Stream<SDKStorageEvent> get storageEvents => _storageController.stream;

  Stream<SDKDeviceEvent> get deviceEvents => _deviceController.stream;

  Stream<SDKEvent> get allEvents => _allEventsController.stream;

  /// Generic event publisher - dispatches to appropriate stream
  void publish(SDKEvent event) {
    _allEventsController.add(event);

    if (event is SDKInitializationEvent) {
      _initializationController.add(event);
    } else if (event is SDKConfigurationEvent) {
      _configurationController.add(event);
    } else if (event is SDKGenerationEvent) {
      _generationController.add(event);
    } else if (event is SDKModelEvent) {
      _modelController.add(event);
    } else if (event is SDKVoiceEvent) {
      _voiceController.add(event);
    } else if (event is SDKStorageEvent) {
      _storageController.add(event);
    } else if (event is SDKDeviceEvent) {
      _deviceController.add(event);
    }
  }

  /// Dispose all controllers
  Future<void> dispose() async {
    await _initializationController.close();
    await _configurationController.close();
    await _generationController.close();
    await _modelController.close();
    await _voiceController.close();
    await _storageController.close();
    await _deviceController.close();
    await _allEventsController.close();
  }
}
