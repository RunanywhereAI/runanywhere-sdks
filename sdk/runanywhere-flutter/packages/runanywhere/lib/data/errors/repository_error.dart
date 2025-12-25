/// Errors that can occur during repository operations
/// Matches iOS RepositoryError from RepositoryError.swift
abstract class RepositoryError implements Exception {
  const RepositoryError();

  String get message;

  @override
  String toString() => 'RepositoryError: $message';
}

class RepositorySyncFailureError extends RepositoryError {
  final String reason;
  const RepositorySyncFailureError(this.reason);

  @override
  String get message => 'Failed to sync: $reason';
}

class RepositoryAuthenticationError extends RepositoryError {
  final String reason;
  const RepositoryAuthenticationError(this.reason);

  @override
  String get message => 'Authentication failed: $reason';
}
