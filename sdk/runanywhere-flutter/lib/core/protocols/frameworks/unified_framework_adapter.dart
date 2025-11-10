import '../../models/framework/framework_modality.dart';
import '../../models/framework/llm_framework.dart';

/// Unified Framework Adapter Protocol
/// Similar to Swift SDK's UnifiedFrameworkAdapter
abstract class UnifiedFrameworkAdapter {
  LLMFramework get framework;
  Set<FrameworkModality> get supportedModalities;

  /// Create a service for a specific modality
  dynamic createService(FrameworkModality modality);
}

