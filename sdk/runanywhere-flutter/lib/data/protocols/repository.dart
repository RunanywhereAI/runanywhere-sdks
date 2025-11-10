/// Base Repository Protocol
/// Similar to Swift SDK's Repository protocol
abstract class Repository<T> {
  /// Save an entity
  Future<void> save(T entity);

  /// Get an entity by ID
  Future<T?> getById(String id);

  /// Get all entities
  Future<List<T>> getAll();

  /// Delete an entity
  Future<void> delete(String id);

  /// Check if entity exists
  Future<bool> exists(String id);
}

