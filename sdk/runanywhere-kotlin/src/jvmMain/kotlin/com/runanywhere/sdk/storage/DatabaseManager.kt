package com.runanywhere.sdk.storage

import com.runanywhere.sdk.foundation.SDKLogger
import java.io.File
import java.sql.Connection
import java.sql.DriverManager

/**
 * Database manager for local caching and model metadata
 * Uses SQLite for lightweight local storage
 */
object DatabaseManager {
    private val logger = SDKLogger("DatabaseManager")
    private var connection: Connection? = null
    private val dbPath = "${System.getProperty("user.home")}/.runanywhere/cache.db"

    /**
     * Initialize database and create tables
     */
    fun initialize() {
        try {
            // Ensure directory exists
            File(dbPath).parentFile?.mkdirs()

            // Connect to SQLite database
            Class.forName("org.sqlite.JDBC")
            connection = DriverManager.getConnection("jdbc:sqlite:$dbPath")

            // Create tables if they don't exist
            createTables()

            logger.info("Database initialized at $dbPath")
        } catch (e: Exception) {
            logger.error("Failed to initialize database", e)
            // Continue without database - not critical
        }
    }

    /**
     * Create required tables
     */
    private fun createTables() {
        connection?.let { conn ->
            // Model metadata table
            conn.createStatement().use { stmt ->
                stmt.execute(
                    """
                    CREATE TABLE IF NOT EXISTS models (
                        id TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        category TEXT NOT NULL,
                        format TEXT NOT NULL,
                        download_url TEXT,
                        local_path TEXT,
                        download_size INTEGER,
                        memory_required INTEGER,
                        downloaded_at INTEGER,
                        last_used_at INTEGER
                    )
                """,
                )
            }

            // Configuration cache table
            conn.createStatement().use { stmt ->
                stmt.execute(
                    """
                    CREATE TABLE IF NOT EXISTS configuration (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL,
                        updated_at INTEGER DEFAULT CURRENT_TIMESTAMP
                    )
                """,
                )
            }

            // Transcription history table
            conn.createStatement().use { stmt ->
                stmt.execute(
                    """
                    CREATE TABLE IF NOT EXISTS transcriptions (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        model_id TEXT NOT NULL,
                        audio_size INTEGER,
                        transcript TEXT,
                        duration_ms INTEGER,
                        created_at INTEGER DEFAULT CURRENT_TIMESTAMP
                    )
                """,
                )
            }
        }
    }

    /**
     * Store model metadata
     */
    fun storeModelMetadata(
        modelId: String,
        name: String,
        category: String,
        format: String,
        localPath: String,
    ) {
        try {
            connection
                ?.prepareStatement(
                    """
                INSERT OR REPLACE INTO models
                (id, name, category, format, local_path, downloaded_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """,
                )?.use { stmt ->
                    stmt.setString(1, modelId)
                    stmt.setString(2, name)
                    stmt.setString(3, category)
                    stmt.setString(4, format)
                    stmt.setString(5, localPath)
                    stmt.setLong(6, System.currentTimeMillis())
                    stmt.executeUpdate()
                }
        } catch (e: Exception) {
            logger.error("Failed to store model metadata", e)
        }
    }

    /**
     * Get model metadata
     */
    fun getModelMetadata(modelId: String): Map<String, Any>? =
        try {
            connection
                ?.prepareStatement(
                    """
                SELECT * FROM models WHERE id = ?
            """,
                )?.use { stmt ->
                    stmt.setString(1, modelId)
                    val rs = stmt.executeQuery()
                    if (rs.next()) {
                        mapOf(
                            "id" to rs.getString("id"),
                            "name" to rs.getString("name"),
                            "category" to rs.getString("category"),
                            "format" to rs.getString("format"),
                            "local_path" to rs.getString("local_path"),
                            "downloaded_at" to rs.getLong("downloaded_at"),
                        )
                    } else {
                        null
                    }
                }
        } catch (e: Exception) {
            logger.error("Failed to get model metadata", e)
            null
        }

    /**
     * Store transcription history
     */
    fun storeTranscription(
        modelId: String,
        audioSize: Int,
        transcript: String,
        durationMs: Long,
    ) {
        try {
            connection
                ?.prepareStatement(
                    """
                INSERT INTO transcriptions
                (model_id, audio_size, transcript, duration_ms)
                VALUES (?, ?, ?, ?)
            """,
                )?.use { stmt ->
                    stmt.setString(1, modelId)
                    stmt.setInt(2, audioSize)
                    stmt.setString(3, transcript)
                    stmt.setLong(4, durationMs)
                    stmt.executeUpdate()
                }
        } catch (e: Exception) {
            logger.error("Failed to store transcription", e)
        }
    }

    /**
     * Close database connection
     */
    fun close() {
        try {
            connection?.close()
            connection = null
            logger.debug("Database connection closed")
        } catch (e: Exception) {
            logger.error("Failed to close database", e)
        }
    }
}
