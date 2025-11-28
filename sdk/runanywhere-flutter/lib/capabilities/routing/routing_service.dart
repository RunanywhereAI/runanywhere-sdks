import '../../../foundation/logging/sdk_logger.dart';
import '../../../foundation/dependency_injection/service_container.dart' show HardwareCapabilityManager, CostCalculator, ResourceChecker;
import '../../../public/runanywhere.dart' show RunAnywhereGenerationOptions;

/// Routing service for determining on-device vs cloud execution
class RoutingService {
  final CostCalculator costCalculator;
  final ResourceChecker resourceChecker;
  final SDKLogger logger = SDKLogger(category: 'RoutingService');

  RoutingService({
    required this.costCalculator,
    required this.resourceChecker,
  });

  /// Determine routing decision for a generation request
  Future<RoutingDecision> determineRouting({
    required String prompt,
    Map<String, dynamic>? context,
    required RunAnywhereGenerationOptions options,
  }) async {
    // For now, default to on-device
    // TODO: Implement actual routing logic based on:
    // - Device capabilities
    // - Model size
    // - Network availability
    // - Cost considerations
    return RoutingDecision.onDevice(framework: null);
  }
}

/// Routing decision
enum RoutingDecisionType {
  onDevice,
  cloud,
  hybrid,
}

class RoutingDecision {
  final RoutingDecisionType type;
  final String? framework;
  final String? provider;
  final double? devicePortion;

  RoutingDecision.onDevice({this.framework})
      : type = RoutingDecisionType.onDevice,
        provider = null,
        devicePortion = null;

  RoutingDecision.cloud({this.provider})
      : type = RoutingDecisionType.cloud,
        framework = null,
        devicePortion = null;

  RoutingDecision.hybrid({
    required this.devicePortion,
    this.framework,
  })  : type = RoutingDecisionType.hybrid,
        provider = null;
}

