package com.runanywhere.sdk.data.database

import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import android.content.Context
import com.runanywhere.sdk.data.database.dao.*
import com.runanywhere.sdk.data.database.entities.*
import com.runanywhere.sdk.data.models.*

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
        AuthTokenEntity::class
    ],
    version = 1,
    exportSchema = true
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
        private var INSTANCE: RunAnywhereDatabase? = null

        fun getDatabase(context: Context): RunAnywhereDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    RunAnywhereDatabase::class.java,
                    DATABASE_NAME
                ).apply {
                    // Database configuration
                    fallbackToDestructiveMigration() // For development
                    enableMultiInstanceInvalidation()

                    // Add migrations when ready for production
                    // addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                }.build()

                INSTANCE = instance
                instance
            }
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
 * Database Manager for KMP compatibility
 * Provides platform-agnostic database access
 */
expect class DatabaseManager {
    suspend fun getDatabase(): RunAnywhereDatabase
    suspend fun closeDatabase()
    suspend fun clearAllData()
}

/**
 * Android implementation of DatabaseManager
 */
class AndroidDatabaseManager(private val context: Context) {

    private var database: RunAnywhereDatabase? = null

    suspend fun getDatabase(): RunAnywhereDatabase {
        return database ?: RunAnywhereDatabase.getDatabase(context).also { database = it }
    }

    suspend fun closeDatabase() {
        database?.close()
        database = null
    }

    suspend fun clearAllData() {
        val db = getDatabase()
        db.clearAllTables()
    }
}
