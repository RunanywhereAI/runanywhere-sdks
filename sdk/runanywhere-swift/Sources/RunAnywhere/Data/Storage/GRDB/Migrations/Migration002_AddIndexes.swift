import Foundation
import GRDB

/// Add database indexes for performance optimization
struct Migration002_AddIndexes {

    static func migrate(_ db: Database) throws {
        // MARK: - Model Metadata Indexes

        // Index for frequently queried fields
        try db.create(index: "idx_model_metadata_format_framework",
                      on: "model_metadata",
                      columns: ["format", "framework"])

        // Index for downloaded models
        try db.create(index: "idx_model_metadata_downloaded",
                      on: "model_metadata",
                      columns: ["is_downloaded", "last_used_at"])

        // Index for model name search
        try db.create(index: "idx_model_metadata_name",
                      on: "model_metadata",
                      columns: ["name"])

        // MARK: - Model Usage Stats Indexes

        // Index for date-based queries
        try db.create(index: "idx_model_usage_stats_date",
                      on: "model_usage_stats",
                      columns: ["date", "model_metadata_id"])

        // MARK: - Generation Sessions Indexes

        // Index for model-based queries
        try db.create(index: "idx_generation_sessions_model",
                      on: "generation_sessions",
                      columns: ["model_metadata_id", "created_at"])

        // Index for active sessions
        try db.create(index: "idx_generation_sessions_active",
                      on: "generation_sessions",
                      columns: ["ended_at"],
                      condition: "ended_at IS NULL")

        // MARK: - Generations Indexes

        // Index for session-based queries
        try db.create(index: "idx_generations_session",
                      on: "generations",
                      columns: ["generation_sessions_id", "sequence_number"])

        // Index for performance analysis
        try db.create(index: "idx_generations_performance",
                      on: "generations",
                      columns: ["execution_target", "created_at"])

        // Index for error tracking
        try db.create(index: "idx_generations_errors",
                      on: "generations",
                      columns: ["error_code"],
                      condition: "error_code IS NOT NULL")

        // MARK: - Telemetry Indexes

        // Index for event queries
        try db.create(index: "idx_telemetry_events",
                      on: "telemetry",
                      columns: ["event_type", "event_name", "timestamp"])

        // Index for session tracking
        try db.create(index: "idx_telemetry_session",
                      on: "telemetry",
                      columns: ["session_id", "timestamp"])

        // Index for sync operations
        try db.create(index: "idx_telemetry_sync",
                      on: "telemetry",
                      columns: ["sync_pending", "created_at"],
                      condition: "sync_pending = 1")

        // MARK: - Configuration Indexes

        // Index for sync operations
        try db.create(index: "idx_configuration_sync",
                      on: "configuration",
                      columns: ["sync_pending", "updated_at"])

        // MARK: - User Preferences Indexes

        // Already has unique constraint on preference_key, which creates an index

        // MARK: - Sync Pending Indexes for All Tables

        try db.create(index: "idx_model_metadata_sync",
                      on: "model_metadata",
                      columns: ["sync_pending", "updated_at"],
                      condition: "sync_pending = 1")

        try db.create(index: "idx_generation_sessions_sync",
                      on: "generation_sessions",
                      columns: ["sync_pending", "updated_at"],
                      condition: "sync_pending = 1")

        try db.create(index: "idx_generations_sync",
                      on: "generations",
                      columns: ["sync_pending", "created_at"],
                      condition: "sync_pending = 1")
    }
}
