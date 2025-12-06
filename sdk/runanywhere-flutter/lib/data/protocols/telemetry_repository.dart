import 'dart:async';

import '../../core/types/telemetry_event_type.dart';
import '../models/telemetry_data.dart';

/// Repository protocol for telemetry data persistence
/// Matches iOS TelemetryRepository from TelemetryRepository.swift
abstract class TelemetryRepository {
  /// Save a telemetry entity
  Future<void> save(TelemetryData entity);

  /// Fetch telemetry by id
  Future<TelemetryData?> fetch(String id);

  /// Fetch all telemetry data
  Future<List<TelemetryData>> fetchAll();

  /// Delete telemetry by id
  Future<void> delete(String id);

  /// Telemetry-specific operations - fetch by date range
  Future<List<TelemetryData>> fetchByDateRange({
    required DateTime from,
    required DateTime to,
  });

  /// Fetch unsent telemetry events
  Future<List<TelemetryData>> fetchUnsent();

  /// Mark telemetry events as sent
  Future<void> markAsSent(List<String> ids);

  /// Cleanup old telemetry events
  Future<void> cleanup({required DateTime olderThan});

  /// Track a new event
  Future<void> trackEvent(
    TelemetryEventType type, {
    Map<String, String> properties = const {},
  });
}
