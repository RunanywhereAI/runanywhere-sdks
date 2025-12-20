package com.runanywhere.sdk.data.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.runanywhere.sdk.data.database.entities.ModelInfoEntity
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory

/**
 * Model Info DAO
 * Room DAO for model information following iOS patterns
 */
@Dao
interface ModelInfoDao {
    @Query("SELECT * FROM model_info WHERE id = :modelId")
    suspend fun getModelById(modelId: String): ModelInfoEntity?

    @Query("SELECT * FROM model_info")
    suspend fun getAllModels(): List<ModelInfoEntity>

    @Query("SELECT * FROM model_info WHERE framework IN (:frameworks)")
    suspend fun getModelsByFrameworks(frameworks: List<InferenceFramework>): List<ModelInfoEntity>

    @Query("SELECT * FROM model_info WHERE category = :category")
    suspend fun getModelsByCategory(category: ModelCategory): List<ModelInfoEntity>

    @Query("SELECT * FROM model_info WHERE is_downloaded = 1")
    suspend fun getDownloadedModels(): List<ModelInfoEntity>

    @Query("SELECT * FROM model_info WHERE is_built_in = 1")
    suspend fun getBuiltInModels(): List<ModelInfoEntity>

    @Query("SELECT * FROM model_info WHERE download_size <= :maxSize")
    suspend fun getModelsBySizeLimit(maxSize: Long): List<ModelInfoEntity>

    @Query(
        """
        SELECT * FROM model_info
        WHERE name LIKE '%' || :query || '%'
        OR description LIKE '%' || :query || '%'
        OR id LIKE '%' || :query || '%'
    """,
    )
    suspend fun searchModels(query: String): List<ModelInfoEntity>

    @Query("SELECT * FROM model_info ORDER BY last_used DESC LIMIT :limit")
    suspend fun getRecentlyUsedModels(limit: Int = 10): List<ModelInfoEntity>

    @Query("SELECT * FROM model_info ORDER BY download_size ASC")
    suspend fun getModelsBySize(): List<ModelInfoEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertModel(model: ModelInfoEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertModels(models: List<ModelInfoEntity>)

    @Update
    suspend fun updateModel(model: ModelInfoEntity)

    @Query("UPDATE model_info SET is_downloaded = :isDownloaded, updated_at = :updatedAt WHERE id = :modelId")
    suspend fun updateDownloadStatus(
        modelId: String,
        isDownloaded: Boolean,
        updatedAt: Long,
    )

    @Query("UPDATE model_info SET download_progress = :progress, updated_at = :updatedAt WHERE id = :modelId")
    suspend fun updateDownloadProgress(
        modelId: String,
        progress: Float,
        updatedAt: Long,
    )

    @Query("UPDATE model_info SET local_path = :localPath, updated_at = :updatedAt WHERE id = :modelId")
    suspend fun updateLocalPath(
        modelId: String,
        localPath: String?,
        updatedAt: Long,
    )

    @Query("UPDATE model_info SET last_used = :lastUsed, updated_at = :updatedAt WHERE id = :modelId")
    suspend fun updateLastUsed(
        modelId: String,
        lastUsed: Long,
        updatedAt: Long,
    )

    @Delete
    suspend fun deleteModel(model: ModelInfoEntity)

    @Query("DELETE FROM model_info WHERE id = :modelId")
    suspend fun deleteModelById(modelId: String)

    @Query("DELETE FROM model_info")
    suspend fun deleteAllModels()

    @Query("DELETE FROM model_info WHERE is_built_in = 0 AND is_downloaded = 0")
    suspend fun deleteUndownloadedModels()

    @Query("SELECT COUNT(*) FROM model_info")
    suspend fun getModelCount(): Int

    @Query("SELECT COUNT(*) FROM model_info WHERE is_downloaded = 1")
    suspend fun getDownloadedModelCount(): Int

    @Query("SELECT SUM(download_size) FROM model_info WHERE is_downloaded = 1")
    suspend fun getTotalDownloadedSize(): Long?
}
