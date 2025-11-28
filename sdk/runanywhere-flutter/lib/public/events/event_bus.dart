import 'dart:async';
import 'sdk_event.dart';
import 'component_initialization_event.dart';

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
  final _generationController = StreamController<SDKGenerationEvent>.broadcast();
  final _modelController = StreamController<SDKModelEvent>.broadcast();
  final _voiceController = StreamController<SDKVoiceEvent>.broadcast();
  final _performanceController =
      StreamController<SDKPerformanceEvent>.broadcast();
  final _networkController = StreamController<SDKNetworkEvent>.broadcast();
  final _storageController = StreamController<SDKStorageEvent>.broadcast();
  final _frameworkController = StreamController<SDKFrameworkEvent>.broadcast();
  final _componentController =
      StreamController<ComponentInitializationEvent>.broadcast();
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

  Stream<SDKPerformanceEvent> get performanceEvents =>
      _performanceController.stream;

  Stream<SDKNetworkEvent> get networkEvents => _networkController.stream;

  Stream<SDKStorageEvent> get storageEvents => _storageController.stream;

  Stream<SDKFrameworkEvent> get frameworkEvents =>
      _frameworkController.stream;

  Stream<ComponentInitializationEvent> get componentEvents =>
      _componentController.stream;

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
    } else if (event is SDKPerformanceEvent) {
      _performanceController.add(event);
    } else if (event is SDKNetworkEvent) {
      _networkController.add(event);
    } else if (event is SDKStorageEvent) {
      _storageController.add(event);
    } else if (event is SDKFrameworkEvent) {
      _frameworkController.add(event);
    } else if (event is ComponentInitializationEvent) {
      _componentController.add(event);
    }
  }

  /// Dispose all controllers
  Future<void> dispose() async {
    await _initializationController.close();
    await _configurationController.close();
    await _generationController.close();
    await _modelController.close();
    await _voiceController.close();
    await _performanceController.close();
    await _networkController.close();
    await _storageController.close();
    await _frameworkController.close();
    await _componentController.close();
    await _allEventsController.close();
  }
}

