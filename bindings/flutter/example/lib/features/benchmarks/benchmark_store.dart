import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_types.dart';

/// JSON persistence for benchmark runs in the app documents directory.
///
/// Mirrors iOS `BenchmarkStore.swift`: one `benchmarks.json` file capped at
/// the most recent [_maxRuns] runs; load/save/clear are best-effort.
class BenchmarkStore {
  static const String _fileName = 'benchmarks.json';
  static const int _maxRuns = 50;

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/$_fileName');
  }

  Future<List<BenchmarkRun>> loadRuns() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return [];
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(BenchmarkRun.fromJson)
          .toList();
    } catch (e) {
      debugPrint('BenchmarkStore: failed to load runs: $e');
      return [];
    }
  }

  Future<void> save(BenchmarkRun run) async {
    try {
      var runs = await loadRuns();
      runs.add(run);
      // Keep only the most recent runs.
      if (runs.length > _maxRuns) {
        runs = runs.sublist(runs.length - _maxRuns);
      }
      final file = await _file();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(runs.map((entry) => entry.toJson()).toList()),
        flush: true,
      );
    } catch (e) {
      debugPrint('BenchmarkStore: failed to save run: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      final file = await _file();
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('BenchmarkStore: failed to clear runs: $e');
    }
  }
}
