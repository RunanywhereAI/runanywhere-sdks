import '../protocols/component/component.dart';
import '../models/common/component_state.dart';
import '../models/common/component_types.dart';

/// Base Component class
/// Similar to Swift SDK's BaseComponent
abstract class BaseComponent implements Component {
  @override
  ComponentState get state => _state;
  ComponentState _state = ComponentState.idle;

  @override
  final ComponentInitParameters parameters;

  BaseComponent({required this.parameters});

  @override
  Future<void> initialize({ComponentInitParameters? parameters}) async {
    if (_state != ComponentState.idle) {
      throw StateError('Component already initialized');
    }

    _state = ComponentState.initializing;
    try {
      await doInitialize(parameters ?? this.parameters);
      _state = ComponentState.ready;
    } catch (e) {
      _state = ComponentState.idle;
      rethrow;
    }
  }

  @override
  Future<void> deinitialize() async {
    if (_state == ComponentState.idle) {
      return;
    }

    _state = ComponentState.deinitializing;
    try {
      await doDeinitialize();
      _state = ComponentState.idle;
    } catch (e) {
      _state = ComponentState.ready;
      rethrow;
    }
  }

  @override
  bool get isInitialized => _state == ComponentState.ready;

  @override
  Future<void> transitionTo(ComponentState newState) async {
    _state = newState;
  }

  /// Override this method to implement component-specific initialization
  Future<void> doInitialize(ComponentInitParameters parameters);

  /// Override this method to implement component-specific cleanup
  Future<void> doDeinitialize();
}

