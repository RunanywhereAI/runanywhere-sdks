import Foundation
import GRDB

/// Initial database schema migration
struct Migration001_InitialSchema {

    static func migrate(_ db: Database) throws {
        // MARK: - Configuration Table

        try db.create(table: "configuration") { t in
            t.primaryKey("id", .text)
            t.column("api_key", .text)
            t.column("base_url", .text).notNull().defaults(to: SDKConstants.DatabaseDefaults.apiBaseURL)
            t.column("model_cache_size", .integer).notNull().defaults(to: SDKConstants.ModelDefaults.defaultModelCacheSize)
            t.column("max_memory_usage_mb", .integer).notNull().defaults(to: SDKConstants.ModelDefaults.defaultMaxMemoryUsageMB)
            t.column("privacy_mode", .text).notNull().defaults(to: SDKConstants.PrivacyDefaults.defaultPrivacyMode)
            t.column("telemetry_consent", .text).notNull().defaults(to: SDKConstants.TelemetryDefaults.consentAnonymous)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("sync_pending", .boolean).notNull().defaults(to: true)
        }

        // MARK: - Routing Policies Table

        try db.create(table: "routing_policies") { t in
            t.primaryKey("id", .text)
            t.belongsTo("configuration", onDelete: .cascade).notNull()
            t.column("policy_type", .text).notNull() // costOptimized, latencyOptimized, privacyFirst, balanced
            t.column("on_device_threshold", .double).notNull().defaults(to: SDKConstants.RoutingDefaults.defaultOnDeviceThreshold)
            t.column("max_cloud_cost_per_request", .double)
            t.column("prefer_on_device", .boolean).notNull().defaults(to: true)
            t.column("created_at", .datetime).notNull()
        }

        // MARK: - Analytics Configuration Table

        try db.create(table: "analytics_config") { t in
            t.primaryKey("id", .text)
            t.belongsTo("configuration", onDelete: .cascade).notNull()
            t.column("analytics_level", .text).notNull().defaults(to: SDKConstants.AnalyticsDefaults.defaultLevel) // basic, detailed, debug
            t.column("metrics_enabled", .boolean).notNull().defaults(to: true)
            t.column("error_reporting_enabled", .boolean).notNull().defaults(to: true)
            t.column("performance_tracking_enabled", .boolean).notNull().defaults(to: true)
            t.column("created_at", .datetime).notNull()
        }

        // MARK: - Storage Configuration Table

        try db.create(table: "storage_config") { t in
            t.primaryKey("id", .text)
            t.belongsTo("configuration", onDelete: .cascade).notNull()
            t.column("max_cache_size_mb", .integer).notNull().defaults(to: SDKConstants.StorageDefaults.defaultMaxCacheSizeMB)
            t.column("auto_cleanup_enabled", .boolean).notNull().defaults(to: true)
            t.column("cleanup_threshold_percentage", .integer).notNull().defaults(to: SDKConstants.StorageDefaults.defaultCleanupThresholdPercentage)
            t.column("model_retention_days", .integer).notNull().defaults(to: SDKConstants.StorageDefaults.defaultModelRetentionDays)
            t.column("created_at", .datetime).notNull()
        }

        // MARK: - Model Metadata Table

        try db.create(table: "model_metadata") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("format", .text).notNull() // gguf, onnx, coreml, mlx, tflite
            t.column("framework", .text).notNull() // LLMFramework enum
            t.column("size_bytes", .integer).notNull()
            t.column("quantization", .text) // none, int8, int4, etc.
            t.column("version", .text).notNull()
            t.column("sha256_hash", .text)

            // Capabilities as JSON
            t.column("capabilities", .blob).notNull() // JSON: max_tokens, supports_streaming, etc.

            // Requirements as JSON
            t.column("requirements", .blob) // JSON: min_memory, min_compute, etc.

            // Download info
            t.column("download_url", .text)
            t.column("local_path", .text)
            t.column("is_downloaded", .boolean).notNull().defaults(to: false)
            t.column("download_date", .datetime)

            // Usage tracking
            t.column("last_used_at", .datetime)
            t.column("use_count", .integer).notNull().defaults(to: 0)
            t.column("total_tokens_generated", .integer).notNull().defaults(to: 0)

            // Timestamps
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("sync_pending", .boolean).notNull().defaults(to: true)

            // Indexes
            t.check(sql: "format IN ('gguf', 'onnx', 'coreml', 'mlx', 'tflite')")
        }

        // MARK: - Model Usage Stats Table

        try db.create(table: "model_usage_stats") { t in
            t.primaryKey("id", .text)
            t.belongsTo("model_metadata", onDelete: .cascade).notNull()
            t.column("date", .date).notNull()
            t.column("generation_count", .integer).notNull().defaults(to: 0)
            t.column("total_tokens", .integer).notNull().defaults(to: 0)
            t.column("total_cost", .double).notNull().defaults(to: 0.0)
            t.column("average_latency_ms", .double)
            t.column("error_count", .integer).notNull().defaults(to: 0)
            t.column("created_at", .datetime).notNull()

            // Unique constraint on model_id + date
            t.uniqueKey(["model_metadata_id", "date"])
        }

        // MARK: - Generation Sessions Table

        try db.create(table: "generation_sessions") { t in
            t.primaryKey("id", .text)
            t.belongsTo("model_metadata").notNull()
            t.column("session_type", .text).notNull() // chat, completion, etc.
            t.column("total_tokens", .integer).notNull().defaults(to: 0)
            t.column("total_cost", .double).notNull().defaults(to: 0.0)
            t.column("message_count", .integer).notNull().defaults(to: 0)
            t.column("context_data", .blob) // JSON: custom context data
            t.column("started_at", .datetime).notNull()
            t.column("ended_at", .datetime)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("sync_pending", .boolean).notNull().defaults(to: true)
        }

        // MARK: - Generations Table

        try db.create(table: "generations") { t in
            t.primaryKey("id", .text)
            t.belongsTo("generation_sessions", onDelete: .cascade).notNull()
            t.column("sequence_number", .integer).notNull()

            // Token counts
            t.column("prompt_tokens", .integer).notNull()
            t.column("completion_tokens", .integer).notNull()
            t.column("total_tokens", .integer).notNull()

            // Performance metrics
            t.column("latency_ms", .double).notNull()
            t.column("tokens_per_second", .double)
            t.column("time_to_first_token_ms", .double)

            // Cost tracking
            t.column("cost", .double).notNull().defaults(to: 0.0)
            t.column("cost_saved", .double).notNull().defaults(to: 0.0)

            // Execution details
            t.column("execution_target", .text).notNull() // onDevice, cloud
            t.column("routing_reason", .text) // costOptimization, latencyOptimization, etc.
            t.column("framework_used", .text) // Actual framework used

            // Request/Response data (optional, for debugging)
            t.column("request_data", .blob) // JSON: prompt, parameters, etc.
            t.column("response_data", .blob) // JSON: completion, finish_reason, etc.

            // Error tracking
            t.column("error_code", .text)
            t.column("error_message", .text)

            // Timestamps
            t.column("created_at", .datetime).notNull()
            t.column("sync_pending", .boolean).notNull().defaults(to: true)

            // Check constraints
            t.check(sql: "execution_target IN ('\(SDKConstants.ExecutionTargets.onDevice)', '\(SDKConstants.ExecutionTargets.cloud)')")
        }

        // MARK: - Telemetry Table

        try db.create(table: "telemetry") { t in
            t.primaryKey("id", .text)
            t.column("event_type", .text).notNull()
            t.column("event_name", .text).notNull()
            t.column("properties", .blob) // JSON: event properties
            t.column("user_id", .text) // Anonymous user ID
            t.column("session_id", .text)
            t.column("device_info", .blob) // JSON: device model, OS version, etc.
            t.column("sdk_version", .text).notNull()
            t.column("timestamp", .datetime).notNull()
            t.column("created_at", .datetime).notNull()
            t.column("sync_pending", .boolean).notNull().defaults(to: true)
        }

        // MARK: - User Preferences Table

        try db.create(table: "user_preferences") { t in
            t.primaryKey("id", .text)
            t.column("preference_key", .text).notNull().unique()
            t.column("preference_value", .blob).notNull() // JSON value
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
        }
    }
}
