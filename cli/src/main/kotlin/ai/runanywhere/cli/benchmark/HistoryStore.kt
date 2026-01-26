package ai.runanywhere.cli.benchmark

import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * SQLite-backed storage for historical benchmark data
 */
class HistoryStore(
    dbPath: File = File(System.getProperty("user.home"), ".runanywhere/benchmark_history.db")
) {
    
    private val connection: Connection
    
    init {
        // Ensure directory exists
        dbPath.parentFile?.mkdirs()
        
        // Connect to SQLite
        Class.forName("org.xerial.JDBC")
        connection = DriverManager.getConnection("jdbc:sqlite:${dbPath.absolutePath}")
        
        // Create tables if not exists
        createTables()
    }
    
    private fun createTables() {
        connection.createStatement().execute("""
            CREATE TABLE IF NOT EXISTS benchmark_results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                model_id TEXT NOT NULL,
                model_name TEXT NOT NULL,
                framework TEXT NOT NULL,
                device_model TEXT NOT NULL,
                platform TEXT NOT NULL,
                os_version TEXT,
                tokens_per_second REAL NOT NULL,
                ttft_ms REAL,
                latency_ms REAL,
                peak_memory_mb REAL,
                model_load_time_ms REAL,
                git_commit TEXT,
                timestamp INTEGER NOT NULL,
                created_at INTEGER DEFAULT (strftime('%s', 'now'))
            )
        """)
        
        connection.createStatement().execute("""
            CREATE INDEX IF NOT EXISTS idx_model_timestamp 
            ON benchmark_results(model_id, timestamp)
        """)
        
        connection.createStatement().execute("""
            CREATE INDEX IF NOT EXISTS idx_platform_timestamp 
            ON benchmark_results(platform, timestamp)
        """)
    }
    
    /**
     * Save a benchmark result
     */
    fun save(result: ResultsAggregator.AggregatedResult) {
        val stmt = connection.prepareStatement("""
            INSERT INTO benchmark_results 
            (model_id, model_name, framework, device_model, platform, os_version,
             tokens_per_second, ttft_ms, latency_ms, peak_memory_mb, model_load_time_ms,
             git_commit, timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """)
        
        stmt.setString(1, result.modelId)
        stmt.setString(2, result.modelName)
        stmt.setString(3, result.framework)
        stmt.setString(4, result.deviceModel)
        stmt.setString(5, result.platform)
        stmt.setString(6, result.osVersion)
        stmt.setDouble(7, result.avgTokensPerSecond)
        stmt.setDouble(8, result.avgTtftMs)
        stmt.setDouble(9, result.avgLatencyMs)
        stmt.setDouble(10, result.peakMemoryMB)
        stmt.setDouble(11, result.modelLoadTimeMs)
        stmt.setString(12, result.gitCommit)
        stmt.setLong(13, result.timestamp)
        
        stmt.executeUpdate()
    }
    
    /**
     * Query historical results
     */
    fun query(
        modelId: String? = null,
        platform: String? = null,
        lastDays: Int = 30,
    ): List<HistoryEntry> {
        val cutoffTime = Instant.now().minusSeconds(lastDays.toLong() * 24 * 60 * 60).epochSecond * 1000
        
        val sql = buildString {
            append("SELECT * FROM benchmark_results WHERE timestamp > ?")
            if (modelId != null) append(" AND model_id = ?")
            if (platform != null) append(" AND platform = ?")
            append(" ORDER BY timestamp DESC")
        }
        
        val stmt = connection.prepareStatement(sql)
        var paramIndex = 1
        stmt.setLong(paramIndex++, cutoffTime)
        if (modelId != null) stmt.setString(paramIndex++, modelId)
        if (platform != null) stmt.setString(paramIndex++, platform)
        
        val results = mutableListOf<HistoryEntry>()
        val rs = stmt.executeQuery()
        
        var previousTps: Double? = null
        
        while (rs.next()) {
            val currentTps = rs.getDouble("tokens_per_second")
            val delta = previousTps?.let { (currentTps - it) / it * 100 } ?: 0.0
            
            results.add(HistoryEntry(
                modelId = rs.getString("model_id"),
                modelName = rs.getString("model_name"),
                platform = rs.getString("platform"),
                deviceModel = rs.getString("device_model"),
                tokensPerSecond = currentTps,
                tokensPerSecondDelta = delta,
                ttftMs = rs.getDouble("ttft_ms"),
                latencyMs = rs.getDouble("latency_ms"),
                peakMemoryMb = rs.getDouble("peak_memory_mb"),
                gitCommit = rs.getString("git_commit"),
                timestamp = rs.getLong("timestamp"),
                dateString = formatDate(rs.getLong("timestamp"))
            ))
            
            previousTps = currentTps
        }
        
        return results
    }
    
    /**
     * Detect performance regression
     */
    fun detectRegression(
        modelId: String,
        currentResult: ResultsAggregator.AggregatedResult,
        thresholdPercent: Double = 10.0,
    ): RegressionReport? {
        // Get baseline (average of last 5 results for this model)
        val stmt = connection.prepareStatement("""
            SELECT AVG(tokens_per_second) as avg_tps,
                   AVG(ttft_ms) as avg_ttft,
                   AVG(latency_ms) as avg_latency
            FROM (
                SELECT tokens_per_second, ttft_ms, latency_ms 
                FROM benchmark_results 
                WHERE model_id = ? 
                ORDER BY timestamp DESC 
                LIMIT 5
            )
        """)
        stmt.setString(1, modelId)
        
        val rs = stmt.executeQuery()
        if (!rs.next()) return null
        
        val baselineTps = rs.getDouble("avg_tps")
        val baselineTtft = rs.getDouble("avg_ttft")
        val baselineLatency = rs.getDouble("avg_latency")
        
        if (baselineTps == 0.0) return null
        
        // Calculate deltas
        val tpsDelta = (currentResult.avgTokensPerSecond - baselineTps) / baselineTps * 100
        val ttftDelta = if (baselineTtft > 0) (currentResult.avgTtftMs - baselineTtft) / baselineTtft * 100 else 0.0
        val latencyDelta = if (baselineLatency > 0) (currentResult.avgLatencyMs - baselineLatency) / baselineLatency * 100 else 0.0
        
        // Check for regression (negative tps delta or positive latency delta beyond threshold)
        val hasRegression = tpsDelta < -thresholdPercent || 
                           ttftDelta > thresholdPercent || 
                           latencyDelta > thresholdPercent
        
        return if (hasRegression) {
            RegressionReport(
                modelId = modelId,
                tokensPerSecondDelta = tpsDelta,
                ttftDelta = ttftDelta,
                latencyDelta = latencyDelta,
                baseline = Baseline(baselineTps, baselineTtft, baselineLatency),
                current = Current(
                    currentResult.avgTokensPerSecond,
                    currentResult.avgTtftMs,
                    currentResult.avgLatencyMs
                ),
                severity = when {
                    tpsDelta < -20.0 || latencyDelta > 30.0 -> Severity.CRITICAL
                    tpsDelta < -10.0 || latencyDelta > 20.0 -> Severity.WARNING
                    else -> Severity.INFO
                }
            )
        } else null
    }
    
    private fun formatDate(timestampMs: Long): String {
        val instant = Instant.ofEpochMilli(timestampMs)
        val date = LocalDate.ofInstant(instant, ZoneId.systemDefault())
        return date.format(DateTimeFormatter.ofPattern("MMM dd"))
    }
    
    fun close() {
        connection.close()
    }
}

data class HistoryEntry(
    val modelId: String,
    val modelName: String,
    val platform: String,
    val deviceModel: String,
    val tokensPerSecond: Double,
    val tokensPerSecondDelta: Double,
    val ttftMs: Double,
    val latencyMs: Double,
    val peakMemoryMb: Double,
    val gitCommit: String?,
    val timestamp: Long,
    val dateString: String,
)

data class RegressionReport(
    val modelId: String,
    val tokensPerSecondDelta: Double,
    val ttftDelta: Double,
    val latencyDelta: Double,
    val baseline: Baseline,
    val current: Current,
    val severity: Severity,
)

data class Baseline(
    val tokensPerSecond: Double,
    val ttftMs: Double,
    val latencyMs: Double,
)

data class Current(
    val tokensPerSecond: Double,
    val ttftMs: Double,
    val latencyMs: Double,
)

enum class Severity {
    INFO,
    WARNING,
    CRITICAL
}
