/// Error categories for logical grouping and filtering
/// Matches iOS ErrorCategory from Foundation/ErrorTypes/ErrorCategory.swift
enum ErrorCategory {
  initialization,
  model,
  generation,
  network,
  storage,
  memory,
  hardware,
  validation,
  authentication,
  component,
  framework,
  unknown;

  /// Initialize from an error by analyzing its type and message
  static ErrorCategory fromError(Object error) {
    final description = error.toString().toLowerCase();

    if (description.contains('memory') ||
        description.contains('out of memory')) {
      return ErrorCategory.memory;
    } else if (description.contains('download') ||
        description.contains('network') ||
        description.contains('connection')) {
      return ErrorCategory.network;
    } else if (description.contains('validation') ||
        description.contains('invalid') ||
        description.contains('checksum')) {
      return ErrorCategory.validation;
    } else if (description.contains('hardware') ||
        description.contains('device') ||
        description.contains('thermal')) {
      return ErrorCategory.hardware;
    } else if (description.contains('auth') ||
        description.contains('credential') ||
        description.contains('api key')) {
      return ErrorCategory.authentication;
    } else if (description.contains('model') || description.contains('load')) {
      return ErrorCategory.model;
    } else if (description.contains('storage') ||
        description.contains('disk') ||
        description.contains('space')) {
      return ErrorCategory.storage;
    } else if (description.contains('initialize') ||
        description.contains('not initialized')) {
      return ErrorCategory.initialization;
    } else if (description.contains('component')) {
      return ErrorCategory.component;
    } else if (description.contains('framework')) {
      return ErrorCategory.framework;
    } else if (description.contains('generation') ||
        description.contains('generate')) {
      return ErrorCategory.generation;
    }

    return ErrorCategory.unknown;
  }
}
