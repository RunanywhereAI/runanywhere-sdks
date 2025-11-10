import '../../models/common/component_state.dart';
import '../../models/common/component_types.dart';

/// Component Protocol
/// Similar to Swift SDK's Component protocol
abstract class Component {
  ComponentState get state;
  ComponentInitParameters get parameters;
  bool get isInitialized;

  Future<void> initialize({ComponentInitParameters? parameters});
  Future<void> deinitialize();
  Future<void> transitionTo(ComponentState state);
}

