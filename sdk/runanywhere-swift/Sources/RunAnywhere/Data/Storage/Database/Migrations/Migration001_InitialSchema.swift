import Foundation
import GRDB

/// Initial database schema migration
struct Migration001_InitialSchema { // swiftlint:disable:this type_name

    // swiftlint:disable:next function_body_length
    static func migrate(_ db: Database) throws {
        // MARK: - Configuration Table
        // Using GRDB's built-in Codable support for nested structures
        // Complex objects (routing, analytics, generation, storage) are stored as JSON

        // swiftlint:disable:next identifier_name
        try db.create(table: "configuration") { t in
            t.primaryKey("id", .text)

            // Complex nested structures stored as JSON blobs via Codable
            t.column("routing", .blob).notNull()     // RoutingConfiguration as JSON
            t.column("analytics", .blob).notNull()   // AnalyticsConfiguration as JSON
            t.column("generation", .blob).notNull()  // GenerationConfiguration as JSON
            t.column("storage", .blob).notNull()     // StorageConfiguration as JSON

            // Simple fields
            t.column("apiKey", .text)
            t.column("allowUserOverride", .boolean).notNull().defaults(to: true)
            t.column("source", .text).notNull().defaults(to: "defaults")

            // Metadata
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("syncPending", .boolean).notNull().defaults(to: false)
        }

        // Create index for source to quickly find consumer overrides
        try db.create(index: "idx_configuration_source",
                     on: "configuration",
                     columns: ["source"])


        // MARK: - Models Table

        // swiftlint:disable:next identifier_name
        try db.create(table: "models") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("category", .text).notNull() // language, speech-recognition, etc.

            // Format and location
            t.column("format", .text).notNull() // gguf, onnx, coreml, mlx, tflite
            t.column("downloadURL", .text)
            t.column("localPath", .text)

            // Size information
            t.column("downloadSize", .integer) // Size in bytes when downloading
            t.column("memoryRequired", .integer) // RAM needed to run the model

            // Framework compatibility (stored as JSON array)
            t.column("compatibleFrameworks", .blob).notNull() // JSON array of frameworks
            t.column("preferredFramework", .text)

            // Model-specific capabilities
            t.column("contextLength", .integer) // For language models
            t.column("supportsThinking", .boolean).notNull().defaults(to: false)

            // Metadata (stored as JSON)
            t.column("metadata", .blob) // JSON: ModelInfoMetadata

            // Tracking fields
            t.column("source", .text).notNull().defaults(to: "remote")
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("syncPending", .boolean).notNull().defaults(to: false)

            // Usage tracking
            t.column("lastUsed", .datetime)
            t.column("usageCount", .integer).notNull().defaults(to: 0)

            // Check constraints
            t.check(sql: "category IN ('language', 'speech-recognition', 'speech-synthesis', 'vision', 'image-generation', 'multimodal', 'audio')")
            t.check(sql: "format IN ('gguf', 'onnx', 'coreml', 'mlx', 'tflite', 'safetensors', 'pytorch', 'mlmodel', 'bnk', 'whisper', 'bin')")
            t.check(sql: "source IN ('defaults', 'remote', 'consumer')")
        }

        // Create indexes for models table
        try db.create(index: "idx_models_category",
                     on: "models",
                     columns: ["category"])

        try db.create(index: "idx_models_format",
                     on: "models",
                     columns: ["format"])

        try db.create(index: "idx_models_localPath",
                     on: "models",
                     columns: ["localPath"])

        try db.create(index: "idx_models_syncPending",
                     on: "models",
                     columns: ["syncPending"])

        try db.create(index: "idx_models_updatedAt",
                     on: "models",
                     columns: ["updatedAt"])

        // MARK: - Model Usage Stats Table

        // swiftlint:disable:next identifier_name
        try db.create(table: "model_usage_stats") { t in
            t.primaryKey("id", .text)
            t.belongsTo("models", onDelete: .cascade).notNull()
            t.column("date", .date).notNull()
            t.column("generation_count", .integer).notNull().defaults(to: 0)
            t.column("total_tokens", .integer).notNull().defaults(to: 0)
            t.column("average_latency_ms", .double)
            t.column("error_count", .integer).notNull().defaults(to: 0)
            t.column("created_at", .datetime).notNull()

            // Unique constraint on model_id + date
            t.uniqueKey(["modelsId", "date"])
        }

        // MARK: - Generation Sessions Table

        // swiftlint:disable:next identifier_name
        try db.create(table: "generation_sessions") { t in
            t.primaryKey("id", .text)
            t.belongsTo("models").notNull()
            t.column("session_type", .text).notNull() // chat, completion, etc.
            t.column("total_tokens", .integer).notNull().defaults(to: 0)
            t.column("message_count", .integer).notNull().defaults(to: 0)
            t.column("context_data", .blob) // JSON: custom context data
            t.column("started_at", .datetime).notNull()
            t.column("ended_at", .datetime)
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
            t.column("sync_pending", .boolean).notNull().defaults(to: true)
        }

        // MARK: - Generations Table

        // swiftlint:disable:next identifier_name
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

            // Execution details
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
        }

        // MARK: - Telemetry Table

        // swiftlint:disable:next identifier_name
        try db.create(table: "telemetry") { t in
            t.primaryKey("id", .text)
            t.column("eventType", .text).notNull()
            t.column("properties", .blob).notNull() // JSON: event properties stored as Data
            t.column("timestamp", .datetime).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("syncPending", .boolean).notNull().defaults(to: true)
        }

        // MARK: - User Preferences Table

        // swiftlint:disable:next identifier_name
        try db.create(table: "user_preferences") { t in
            t.primaryKey("id", .text)
            t.column("preference_key", .text).notNull().unique()
            t.column("preference_value", .blob).notNull() // JSON value
            t.column("created_at", .datetime).notNull()
            t.column("updated_at", .datetime).notNull()
        }
    }
}
