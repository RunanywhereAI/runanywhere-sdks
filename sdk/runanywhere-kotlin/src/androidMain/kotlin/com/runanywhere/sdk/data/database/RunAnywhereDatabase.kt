package com.runanywhere.sdk.data.database

import android.annotation.SuppressLint
import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.runanywhere.sdk.data.database.dao.AuthTokenDao
import com.runanywhere.sdk.data.database.dao.ConfigurationDao
import com.runanywhere.sdk.data.database.dao.DeviceInfoDao
import com.runanywhere.sdk.data.database.dao.ModelInfoDao
import com.runanywhere.sdk.data.database.dao.TelemetryDao
import com.runanywhere.sdk.data.database.entities.AuthTokenEntity
import com.runanywhere.sdk.data.database.entities.ConfigurationEntity
import com.runanywhere.sdk.data.database.entities.DeviceInfoEntity
import com.runanywhere.sdk.data.database.entities.ModelInfoEntity
import com.runanywhere.sdk.data.database.entities.TelemetryEventEntity

/**
 * RunAnywhere Room Database
 * KMP-compatible database setup using existing models
 * Matches iOS Core Data structure patterns
 */
@Database(
    entities = [
        ConfigurationEntity::class,
        ModelInfoEntity::class,
        DeviceInfoEntity::class,
        TelemetryEventEntity::class,
        AuthTokenEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
@TypeConverters(DatabaseConverters::class)
abstract class RunAnywhereDatabase : RoomDatabase() {
    // DAOs - following iOS repository patterns
    abstract fun configurationDao(): ConfigurationDao

    abstract fun modelInfoDao(): ModelInfoDao

    abstract fun deviceInfoDao(): DeviceInfoDao

    abstract fun telemetryDao(): TelemetryDao

    abstract fun authTokenDao(): AuthTokenDao

    companion object {
        private const val DATABASE_NAME = "runanywhere_database"

        @Volatile
        private var instance: RunAnywhereDatabase? = null

        fun getDatabase(context: Context): RunAnywhereDatabase =
            instance ?: synchronized(this) {
                val newInstance =
                    Room
                        .databaseBuilder(
                            context.applicationContext,
                            RunAnywhereDatabase::class.java,
                            DATABASE_NAME,
                        ).apply {
                            // Database configuration
                            fallbackToDestructiveMigration() // For development
                            enableMultiInstanceInvalidation()

                            // Add migrations when ready for production
                            // addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                        }.build()

                instance = newInstance
                newInstance
            }

        // Database migration examples for future versions
        // private val MIGRATION_1_2 = object : Migration(1, 2) {
        //     override fun migrate(database: SupportSQLiteDatabase) {
        //         // Migration logic
        //     }
        // }
    }
}

/**
 * Database Manager for Android
 * Provides database access
 */
@SuppressLint("StaticFieldLeak") // Using applicationContext which is safe (doesn't leak Activity)
class DatabaseManager {
    private lateinit var context: Context
    private var database: RunAnywhereDatabase? = null

    suspend fun getDatabase(): RunAnywhereDatabase = database ?: RunAnywhereDatabase.getDatabase(context).also { database = it }

    suspend fun closeDatabase() {
        database?.close()
        database = null
    }

    suspend fun clearAllData() {
        database?.clearAllTables()
    }

    companion object {
        val shared: DatabaseManager = DatabaseManager()

        fun initialize(context: Any) {
            if (context is Context) {
                shared.context = context
            }
        }
    }
}

// Keep the original for backwards compatibility if needed
class AndroidDatabaseManager(
    private val context: Context,
) {
    private var database: RunAnywhereDatabase? = null

    suspend fun getDatabase(): RunAnywhereDatabase = database ?: RunAnywhereDatabase.getDatabase(context).also { database = it }

    suspend fun closeDatabase() {
        database?.close()
        database = null
    }

    suspend fun clearAllData() {
        val db = getDatabase()
        db.clearAllTables()
    }
}
