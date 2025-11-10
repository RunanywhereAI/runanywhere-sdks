import '../models/entities/configuration_entity.dart';
import 'repository.dart';

/// Configuration Repository Protocol
/// Similar to Swift SDK's ConfigurationRepository
abstract class ConfigurationRepository extends Repository<ConfigurationEntity> {
  /// Get current configuration
  Future<ConfigurationEntity?> getCurrentConfiguration();

  /// Save configuration
  Future<void> saveConfiguration(ConfigurationEntity configuration);
}

