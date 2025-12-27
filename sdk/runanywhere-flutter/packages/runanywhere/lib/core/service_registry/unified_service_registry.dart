import 'package:runanywhere/core/models/framework/framework_modality.dart';
import 'package:runanywhere/core/models/framework/llm_framework.dart';
import 'package:runanywhere/core/models/model/model_info.dart';
import 'package:runanywhere/core/protocols/frameworks/unified_framework_adapter.dart';

/// Wrapper for adapters with priority and metadata
class _RegisteredAdapter {
  final UnifiedFrameworkAdapter adapter;
  final int priority;
  final DateTime registrationDate;

  _RegisteredAdapter({
    required this.adapter,
    required this.priority,
    required this.registrationDate,
  });
}

/// Registry for managing multiple adapters per service type
/// Matches iOS UnifiedServiceRegistry from Core/ServiceRegistry/UnifiedServiceRegistry.swift
class UnifiedServiceRegistry {
  /// Storage: modality -> array of registered adapters
  final Map<FrameworkModality, List<_RegisteredAdapter>> _adaptersByModality =
      {};

  /// Legacy storage for backward compatibility: framework -> adapter
  final Map<LLMFramework, UnifiedFrameworkAdapter> _adaptersByFramework = {};

  UnifiedServiceRegistry();

  /// Register an adapter with priority
  /// Higher priority = preferred selection (default: 100)
  void register(UnifiedFrameworkAdapter adapter, {int priority = 100}) {
    // Store in legacy framework map for backward compatibility
    _adaptersByFramework[adapter.framework] = adapter;

    // Store by modality with priority
    for (final modality in adapter.supportedModalities) {
      final adapters = _adaptersByModality[modality] ?? [];

      // Remove existing adapter with same framework to avoid duplicates
      adapters.removeWhere((a) => a.adapter.framework == adapter.framework);

      // Add new adapter
      adapters.add(_RegisteredAdapter(
        adapter: adapter,
        priority: priority,
        registrationDate: DateTime.now(),
      ));

      // Sort by priority (higher first), then by registration date (earlier first)
      adapters.sort((lhs, rhs) {
        if (lhs.priority != rhs.priority) {
          return rhs.priority.compareTo(lhs.priority);
        }
        return lhs.registrationDate.compareTo(rhs.registrationDate);
      });

      _adaptersByModality[modality] = adapters;
    }
  }

  /// Get all adapters that can handle a model for a given modality
  List<UnifiedFrameworkAdapter> findAdapters({
    required ModelInfo model,
    required FrameworkModality modality,
  }) {
    final registered = _adaptersByModality[modality];
    if (registered == null) {
      return [];
    }

    return registered
        .map((r) => r.adapter)
        .where((adapter) => adapter.canHandle(model))
        .toList();
  }

  /// Find the best adapter for a model based on preferences
  UnifiedFrameworkAdapter? findBestAdapter({
    required ModelInfo model,
    required FrameworkModality modality,
  }) {
    final adapters = findAdapters(model: model, modality: modality);

    if (adapters.isEmpty) {
      return null;
    }

    // Priority 1: Preferred framework specified in model
    final preferred = model.preferredFramework;
    if (preferred != null) {
      final match = adapters.cast<UnifiedFrameworkAdapter?>().firstWhere(
            (a) => a?.framework == preferred,
            orElse: () => null,
          );
      if (match != null) {
        return match;
      }
    }

    // Priority 2: Compatible frameworks in order
    for (final framework in model.compatibleFrameworks) {
      final match = adapters.cast<UnifiedFrameworkAdapter?>().firstWhere(
            (a) => a?.framework == framework,
            orElse: () => null,
          );
      if (match != null) {
        return match;
      }
    }

    // Priority 3: First capable adapter (already sorted by priority)
    return adapters.first;
  }

  /// Get adapter by framework (for backward compatibility)
  UnifiedFrameworkAdapter? getAdapter(LLMFramework framework) {
    return _adaptersByFramework[framework];
  }

  /// Get all registered frameworks for a modality
  List<LLMFramework> getFrameworks(FrameworkModality modality) {
    final registered = _adaptersByModality[modality];
    if (registered == null) {
      return [];
    }
    return registered.map((r) => r.adapter.framework).toList();
  }

  /// Get all registered adapters across all modalities
  List<UnifiedFrameworkAdapter> getAllAdapters() {
    return _adaptersByFramework.values.toList();
  }

  /// Find all adapters (including fallbacks) for a model and modality
  List<UnifiedFrameworkAdapter> findAllAdapters({
    required ModelInfo model,
    required FrameworkModality modality,
  }) {
    return findAdapters(model: model, modality: modality);
  }

  /// Get available frameworks (frameworks with registered adapters)
  List<LLMFramework> getAvailableFrameworks() {
    return _adaptersByFramework.keys.toList();
  }
}
