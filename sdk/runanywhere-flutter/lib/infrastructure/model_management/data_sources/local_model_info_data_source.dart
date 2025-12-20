//
//  local_model_info_data_source.dart
//  RunAnywhere SDK
//
//  Local data source for managing model info in SQLite database
//  Matches iOS SDK's LocalModelInfoDataSource.swift
//

import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/models/framework/llm_framework.dart';
import '../../../core/models/framework/model_format.dart';
import '../../../core/models/model/model_category.dart';
import '../../../core/models/model/model_info.dart';
import '../../../foundation/logging/sdk_logger.dart';
import '../../analytics/data_sources/local_telemetry_data_source.dart';

/// Constants for model info database
class ModelInfoConstants {
  static const String databaseName = 'runanywhere_models.db';
  static const int databaseVersion = 1;

  /// Table name for models
  static const String tableName = 'models';
}

/// SQL statements for model info table
const String createModelsTableSql = '''
CREATE TABLE IF NOT EXISTS ${ModelInfoConstants.tableName} (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  format TEXT NOT NULL,
  download_url TEXT,
  local_path TEXT,
  download_size INTEGER,
  memory_required INTEGER,
  compatible_frameworks TEXT NOT NULL,
  preferred_framework TEXT,
  context_length INTEGER,
  supports_thinking INTEGER DEFAULT 0,
  thinking_pattern TEXT,
  metadata TEXT,
  artifact_type TEXT,
  source TEXT DEFAULT 'remote',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  sync_pending INTEGER DEFAULT 0,
  last_used INTEGER,
  usage_count INTEGER DEFAULT 0
)
''';

const String createModelsTimestampIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_models_updated_at
ON ${ModelInfoConstants.tableName} (updated_at DESC)
''';

const String createModelsSyncPendingIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_models_sync_pending
ON ${ModelInfoConstants.tableName} (sync_pending)
''';

const String createModelsCategoryIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_models_category
ON ${ModelInfoConstants.tableName} (category)
''';

/// Local data source for managing model info in SQLite database
class LocalModelInfoDataSource {
  final SDKLogger _logger = SDKLogger(category: 'LocalModelInfoDataSource');

  Database? _database;
  bool _isInitialized = false;

  /// Singleton instance
  static final LocalModelInfoDataSource shared = LocalModelInfoDataSource._();

  LocalModelInfoDataSource._();

  /// Factory constructor for testing with custom database
  LocalModelInfoDataSource.withDatabase(Database database)
      : _database = database,
        _isInitialized = true;

  /// Initialize the database
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final dbPath =
          '${documentsDirectory.path}/${ModelInfoConstants.databaseName}';

      _database = await openDatabase(
        dbPath,
        version: ModelInfoConstants.databaseVersion,
        onCreate: (db, version) async {
          await db.execute(createModelsTableSql);
          await db.execute(createModelsTimestampIndexSql);
          await db.execute(createModelsSyncPendingIndexSql);
          await db.execute(createModelsCategoryIndexSql);
          _logger.info('Models database created');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // Handle migrations here if needed
          _logger
              .info('Models database upgraded from $oldVersion to $newVersion');
        },
      );

      _isInitialized = true;
      _logger.info('LocalModelInfoDataSource initialized');
    } catch (e) {
      _logger.error('Failed to initialize database: $e');
      throw DataSourceException(
        DataSourceError.databaseError,
        message: 'Failed to initialize database',
        cause: e,
      );
    }
  }

  /// Check if the data source is available
  Future<bool> isAvailable() async {
    if (!_isInitialized || _database == null) return false;

    try {
      final result = await _database!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='${ModelInfoConstants.tableName}'",
      );
      return result.isNotEmpty;
    } catch (e) {
      _logger.debug('Database table not available: $e');
      return false;
    }
  }

  /// Validate configuration
  Future<void> validateConfiguration() async {
    if (!await isAvailable()) {
      throw const DataSourceException(DataSourceError.storageUnavailable);
    }
  }

  // MARK: - CRUD Operations

  /// Load a single model by ID
  Future<ModelInfo?> load(String id) async {
    await _ensureInitialized();
    _logger.debug('Loading model: $id');

    try {
      final result = await _database!.query(
        ModelInfoConstants.tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (result.isEmpty) return null;
      return _modelInfoFromRow(result.first);
    } catch (e) {
      _logger.error('Failed to load model: $e');
      rethrow;
    }
  }

  /// Load all models (ordered by updated_at descending)
  Future<List<ModelInfo>> loadAll() async {
    await _ensureInitialized();
    _logger.debug('Loading all models');

    try {
      final result = await _database!.query(
        ModelInfoConstants.tableName,
        orderBy: 'updated_at DESC',
      );

      return result.map((row) => _modelInfoFromRow(row)).toList();
    } catch (e) {
      _logger.error('Failed to load all models: $e');
      rethrow;
    }
  }

  /// Store a model
  Future<void> store(ModelInfo entity) async {
    await _ensureInitialized();
    _logger.debug('Storing model: ${entity.id}');

    try {
      final row = _rowFromModelInfo(entity.copyWith(
        updatedAt: DateTime.now(),
        syncPending: true,
      ));

      await _database!.insert(
        ModelInfoConstants.tableName,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _logger.debug('Model stored successfully: ${entity.id}');
    } catch (e) {
      _logger.error('Failed to store model: $e');
      rethrow;
    }
  }

  /// Remove a model by ID
  Future<bool> remove(String id) async {
    await _ensureInitialized();
    _logger.debug('Removing model: $id');

    try {
      final deleted = await _database!.delete(
        ModelInfoConstants.tableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (deleted > 0) {
        _logger.debug('Model removed successfully: $id');
        return true;
      } else {
        _logger.debug('Model not found for removal: $id');
        return false;
      }
    } catch (e) {
      _logger.error('Failed to remove model: $e');
      rethrow;
    }
  }

  /// Clear all models
  Future<int> clear() async {
    await _ensureInitialized();
    _logger.debug('Clearing all models');

    try {
      final deletedCount =
          await _database!.delete(ModelInfoConstants.tableName);
      _logger.info('Cleared $deletedCount models');
      return deletedCount;
    } catch (e) {
      _logger.error('Failed to clear models: $e');
      rethrow;
    }
  }

  /// Get storage information
  Future<DataSourceStorageInfo> getStorageInfo() async {
    await _ensureInitialized();

    try {
      final countResult = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM ${ModelInfoConstants.tableName}',
      );
      final count = Sqflite.firstIntValue(countResult) ?? 0;

      return DataSourceStorageInfo(
        entityCount: count,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      _logger.error('Failed to get storage info: $e');
      rethrow;
    }
  }

  // MARK: - Model-specific queries

  /// Find models by framework
  Future<List<ModelInfo>> findByFramework(LLMFramework framework) async {
    await _ensureInitialized();

    try {
      // We need to search within the JSON array of compatible_frameworks
      final result = await _database!.query(
        ModelInfoConstants.tableName,
        where: 'compatible_frameworks LIKE ?',
        whereArgs: ['%"${framework.rawValue}"%'],
        orderBy: 'updated_at DESC',
      );

      return result.map((row) => _modelInfoFromRow(row)).toList();
    } catch (e) {
      _logger.error('Failed to find models by framework: $e');
      rethrow;
    }
  }

  /// Find models by category
  Future<List<ModelInfo>> findByCategory(ModelCategory category) async {
    await _ensureInitialized();

    try {
      final result = await _database!.query(
        ModelInfoConstants.tableName,
        where: 'category = ?',
        whereArgs: [category.rawValue],
        orderBy: 'updated_at DESC',
      );

      return result.map((row) => _modelInfoFromRow(row)).toList();
    } catch (e) {
      _logger.error('Failed to find models by category: $e');
      rethrow;
    }
  }

  /// Find downloaded models (those with local_path set)
  Future<List<ModelInfo>> findDownloaded() async {
    await _ensureInitialized();

    try {
      final result = await _database!.query(
        ModelInfoConstants.tableName,
        where: 'local_path IS NOT NULL AND local_path != ?',
        whereArgs: [''],
        orderBy: 'last_used DESC',
      );

      // Filter to only return models that are actually downloaded
      return result
          .map((row) => _modelInfoFromRow(row))
          .where((m) => m.isDownloaded)
          .toList();
    } catch (e) {
      _logger.error('Failed to find downloaded models: $e');
      rethrow;
    }
  }

  // MARK: - Sync operations

  /// Load pending sync models
  Future<List<ModelInfo>> loadPendingSync() async {
    await _ensureInitialized();

    try {
      final result = await _database!.query(
        ModelInfoConstants.tableName,
        where: 'sync_pending = ?',
        whereArgs: [1],
        limit: 100, // Batch size
      );

      return result.map((row) => _modelInfoFromRow(row)).toList();
    } catch (e) {
      _logger.error('Failed to load pending sync models: $e');
      rethrow;
    }
  }

  /// Mark models as synced
  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    await _ensureInitialized();

    try {
      await _database!.transaction((txn) async {
        for (final id in ids) {
          await txn.update(
            ModelInfoConstants.tableName,
            {'sync_pending': 0},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      });

      _logger.debug('Marked ${ids.length} models as synced');
    } catch (e) {
      _logger.error('Failed to mark models as synced: $e');
      rethrow;
    }
  }

  // MARK: - Download status updates

  /// Update download status for a model
  Future<void> updateDownloadStatus(String modelId, Uri? localPath) async {
    await _ensureInitialized();

    try {
      await _database!.update(
        ModelInfoConstants.tableName,
        {
          'local_path': localPath?.toString(),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'sync_pending': 1,
        },
        where: 'id = ?',
        whereArgs: [modelId],
      );

      _logger.debug('Updated download status for model: $modelId');
    } catch (e) {
      _logger.error('Failed to update download status: $e');
      rethrow;
    }
  }

  /// Update last used timestamp for a model
  Future<void> updateLastUsed(String modelId) async {
    await _ensureInitialized();

    try {
      await _database!.rawUpdate('''
        UPDATE ${ModelInfoConstants.tableName}
        SET last_used = ?,
            usage_count = usage_count + 1,
            updated_at = ?,
            sync_pending = 1
        WHERE id = ?
      ''', [
        DateTime.now().millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
        modelId,
      ]);

      _logger.debug('Updated last used for model: $modelId');
    } catch (e) {
      _logger.error('Failed to update last used: $e');
      rethrow;
    }
  }

  /// Close the database
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
      _isInitialized = false;
      _logger.info('LocalModelInfoDataSource closed');
    }
  }

  // MARK: - Private helpers

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_database == null) {
      throw const DataSourceException(
        DataSourceError.storageUnavailable,
        message: 'Database not available',
      );
    }
  }

  /// Convert database row to ModelInfo
  ModelInfo _modelInfoFromRow(Map<String, dynamic> row) {
    // Parse compatible frameworks from JSON
    List<LLMFramework> compatibleFrameworks = [];
    final frameworksJson = row['compatible_frameworks'] as String?;
    if (frameworksJson != null && frameworksJson.isNotEmpty) {
      try {
        final List<dynamic> frameworksList = jsonDecode(frameworksJson);
        compatibleFrameworks = frameworksList
            .map((f) => LLMFramework.fromRawValue(f as String))
            .whereType<LLMFramework>()
            .toList();
      } catch (e) {
        _logger.debug('Failed to parse compatible_frameworks: $e');
      }
    }

    // Parse preferred framework
    LLMFramework? preferredFramework;
    final preferredRaw = row['preferred_framework'] as String?;
    if (preferredRaw != null) {
      preferredFramework = LLMFramework.fromRawValue(preferredRaw);
    }

    return ModelInfo(
      id: row['id'] as String,
      name: row['name'] as String,
      category: ModelCategory.fromRawValue(row['category'] as String) ??
          ModelCategory.language,
      format: ModelFormat.fromRawValue(row['format'] as String),
      downloadURL: row['download_url'] != null
          ? Uri.tryParse(row['download_url'] as String)
          : null,
      localPath: row['local_path'] != null
          ? Uri.tryParse(row['local_path'] as String)
          : null,
      downloadSize: row['download_size'] as int?,
      memoryRequired: row['memory_required'] as int?,
      compatibleFrameworks: compatibleFrameworks,
      preferredFramework: preferredFramework,
      contextLength: row['context_length'] as int?,
      supportsThinking: (row['supports_thinking'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      syncPending: (row['sync_pending'] as int?) == 1,
      lastUsed: row['last_used'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['last_used'] as int)
          : null,
      usageCount: row['usage_count'] as int? ?? 0,
    );
  }

  /// Convert ModelInfo to database row
  Map<String, dynamic> _rowFromModelInfo(ModelInfo model) {
    return {
      'id': model.id,
      'name': model.name,
      'category': model.category.rawValue,
      'format': model.format.rawValue,
      'download_url': model.downloadURL?.toString(),
      'local_path': model.localPath?.toString(),
      'download_size': model.downloadSize,
      'memory_required': model.memoryRequired,
      'compatible_frameworks': jsonEncode(
          model.compatibleFrameworks.map((f) => f.rawValue).toList()),
      'preferred_framework': model.preferredFramework?.rawValue,
      'context_length': model.contextLength,
      'supports_thinking': model.supportsThinking ? 1 : 0,
      'thinking_pattern': model.thinkingPattern?.toJson().toString(),
      'metadata': model.metadata?.toJson().toString(),
      'source': model.source.rawValue,
      'created_at': model.createdAt.millisecondsSinceEpoch,
      'updated_at': model.updatedAt.millisecondsSinceEpoch,
      'sync_pending': model.syncPending ? 1 : 0,
      'last_used': model.lastUsed?.millisecondsSinceEpoch,
      'usage_count': model.usageCount,
    };
  }
}
