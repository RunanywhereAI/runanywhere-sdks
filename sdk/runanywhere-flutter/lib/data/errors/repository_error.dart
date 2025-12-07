/// Errors that can occur during repository operations
/// Matches iOS RepositoryError from RepositoryError.swift
abstract class RepositoryError implements Exception {
  const RepositoryError();

  String get message;

  @override
  String toString() => 'RepositoryError: $message';
}

class RepositorySaveFailureError extends RepositoryError {
  final String reason;
  const RepositorySaveFailureError(this.reason);

  @override
  String get message => 'Failed to save: $reason';
}

class RepositoryFetchFailureError extends RepositoryError {
  final String reason;
  const RepositoryFetchFailureError(this.reason);

  @override
  String get message => 'Failed to fetch: $reason';
}

class RepositoryDeleteFailureError extends RepositoryError {
  final String reason;
  const RepositoryDeleteFailureError(this.reason);

  @override
  String get message => 'Failed to delete: $reason';
}

class RepositorySyncFailureError extends RepositoryError {
  final String reason;
  const RepositorySyncFailureError(this.reason);

  @override
  String get message => 'Failed to sync: $reason';
}

class RepositoryDatabaseNotInitializedError extends RepositoryError {
  const RepositoryDatabaseNotInitializedError();

  @override
  String get message => 'Database not initialized';
}

class RepositoryEntityNotFoundError extends RepositoryError {
  final String id;
  const RepositoryEntityNotFoundError(this.id);

  @override
  String get message => 'Entity not found: $id';
}

class RepositoryNetworkUnavailableError extends RepositoryError {
  const RepositoryNetworkUnavailableError();

  @override
  String get message => 'Network unavailable for sync';
}

class RepositoryNetworkNotAvailableError extends RepositoryError {
  const RepositoryNetworkNotAvailableError();

  @override
  String get message => 'Network not available';
}

class RepositoryNetworkError extends RepositoryError {
  final Object error;
  const RepositoryNetworkError(this.error);

  @override
  String get message => 'Network error: $error';
}

class RepositoryNetworkTimeoutError extends RepositoryError {
  const RepositoryNetworkTimeoutError();

  @override
  String get message => 'Network request timed out';
}
