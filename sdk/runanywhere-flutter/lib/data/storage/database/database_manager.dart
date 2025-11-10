import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Database Manager for SQLite operations
/// Similar to Swift SDK's DatabaseManager
class DatabaseManager {
  static final DatabaseManager shared = DatabaseManager._();
  DatabaseManager._();

  Database? _database;

  /// Initialize database
  Future<void> setup() async {
    if (_database != null) return;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = path.join(documentsDirectory.path, 'runanywhere.db');

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        // Create configurations table
        await db.execute('''
          CREATE TABLE configurations (
            id TEXT PRIMARY KEY,
            apiKey TEXT NOT NULL,
            baseURL TEXT NOT NULL,
            environment TEXT NOT NULL,
            data TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');

        // Create model_metadata table
        await db.execute('''
          CREATE TABLE model_metadata (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            format TEXT,
            framework TEXT,
            memoryRequirement INTEGER,
            downloadURL TEXT,
            localPath TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');

        // Create telemetry table
        await db.execute('''
          CREATE TABLE telemetry (
            id TEXT PRIMARY KEY,
            eventType TEXT NOT NULL,
            data TEXT NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');
      },
    );
  }

  /// Get database instance
  Database get database {
    if (_database == null) {
      throw StateError('Database not initialized. Call setup() first.');
    }
    return _database!;
  }

  /// Insert data
  Future<void> insert(String table, Map<String, dynamic> data) async {
    await database.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Query data
  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return await database.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Update data
  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    return await database.update(table, values, where: where, whereArgs: whereArgs);
  }

  /// Delete data
  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    return await database.delete(table, where: where, whereArgs: whereArgs);
  }

  /// Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

