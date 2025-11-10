import '../protocols/configuration_repository.dart';
import '../models/entities/configuration_entity.dart';
import '../storage/database/database_manager.dart';

/// Configuration Repository Implementation
class ConfigurationRepositoryImpl implements ConfigurationRepository {
  final DatabaseManager _database;

  ConfigurationRepositoryImpl({required DatabaseManager database})
      : _database = database;

  @override
  Future<void> save(ConfigurationEntity entity) async {
    await _database.insert('configurations', entity.toJson());
  }

  @override
  Future<ConfigurationEntity?> getById(String id) async {
    final result = await _database.query('configurations', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return ConfigurationEntity.fromJson(result.first);
  }

  @override
  Future<List<ConfigurationEntity>> getAll() async {
    final results = await _database.query('configurations');
    return results.map((json) => ConfigurationEntity.fromJson(json)).toList();
  }

  @override
  Future<void> delete(String id) async {
    await _database.delete('configurations', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<bool> exists(String id) async {
    final result = await getById(id);
    return result != null;
  }

  @override
  Future<ConfigurationEntity?> getCurrentConfiguration() async {
    final all = await getAll();
    if (all.isEmpty) return null;
    // Return the most recent configuration
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return all.first;
  }

  @override
  Future<void> saveConfiguration(ConfigurationEntity configuration) async {
    await save(configuration);
  }
}

