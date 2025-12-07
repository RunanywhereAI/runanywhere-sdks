import '../models/framework/llm_framework.dart';
import '../models/framework/framework_modality.dart';
import '../models/model/model_info.dart';
import '../protocols/frameworks/unified_framework_adapter.dart';

/// Strategy for selecting the best adapter from multiple candidates
/// Matches iOS AdapterSelectionStrategy from Core/ServiceRegistry/AdapterSelectionStrategy.swift
abstract class AdapterSelectionStrategy {
  UnifiedFrameworkAdapter? selectAdapter({
    required List<UnifiedFrameworkAdapter> candidates,
    required ModelInfo model,
    required FrameworkModality modality,
  });
}

/// Default strategy: Prefer model's preferredFramework, then compatible frameworks
class DefaultAdapterSelectionStrategy implements AdapterSelectionStrategy {
  const DefaultAdapterSelectionStrategy();

  @override
  UnifiedFrameworkAdapter? selectAdapter({
    required List<UnifiedFrameworkAdapter> candidates,
    required ModelInfo model,
    required FrameworkModality modality,
  }) {
    if (candidates.isEmpty) {
      return null;
    }

    // Priority 1: Preferred framework from model
    final preferred = model.preferredFramework;
    if (preferred != null) {
      final match = candidates.cast<UnifiedFrameworkAdapter?>().firstWhere(
            (a) => a?.framework == preferred,
            orElse: () => null,
          );
      if (match != null) {
        return match;
      }
    }

    // Priority 2: Compatible frameworks in order
    for (final framework in model.compatibleFrameworks) {
      final match = candidates.cast<UnifiedFrameworkAdapter?>().firstWhere(
            (a) => a?.framework == framework,
            orElse: () => null,
          );
      if (match != null) {
        return match;
      }
    }

    // Priority 3: First capable adapter
    return candidates.first;
  }
}

/// Pattern-based strategy: Select adapter based on model ID patterns
class PatternBasedAdapterSelectionStrategy implements AdapterSelectionStrategy {
  final Map<String, LLMFramework> patterns;

  /// Initialize with patterns mapping model ID substrings to frameworks
  /// Example: {'whisper': LLMFramework.whisperKit, 'moonshine': LLMFramework.moonshine}
  PatternBasedAdapterSelectionStrategy({required this.patterns});

  @override
  UnifiedFrameworkAdapter? selectAdapter({
    required List<UnifiedFrameworkAdapter> candidates,
    required ModelInfo model,
    required FrameworkModality modality,
  }) {
    if (candidates.isEmpty) {
      return null;
    }

    // Check patterns in model ID
    final modelIdLower = model.id.toLowerCase();
    for (final entry in patterns.entries) {
      if (modelIdLower.contains(entry.key.toLowerCase())) {
        final match = candidates.cast<UnifiedFrameworkAdapter?>().firstWhere(
              (a) => a?.framework == entry.value,
              orElse: () => null,
            );
        if (match != null) {
          return match;
        }
      }
    }

    // Fallback to default strategy
    return const DefaultAdapterSelectionStrategy().selectAdapter(
      candidates: candidates,
      model: model,
      modality: modality,
    );
  }
}

/// Explicit framework strategy: Always prefer a specific framework
class ExplicitFrameworkStrategy implements AdapterSelectionStrategy {
  final LLMFramework preferredFramework;

  ExplicitFrameworkStrategy({required this.preferredFramework});

  @override
  UnifiedFrameworkAdapter? selectAdapter({
    required List<UnifiedFrameworkAdapter> candidates,
    required ModelInfo model,
    required FrameworkModality modality,
  }) {
    // Try to find preferred framework
    final match = candidates.cast<UnifiedFrameworkAdapter?>().firstWhere(
          (a) => a?.framework == preferredFramework,
          orElse: () => null,
        );
    if (match != null) {
      return match;
    }

    // Fallback to first available
    return candidates.isNotEmpty ? candidates.first : null;
  }
}
