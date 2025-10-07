package com.runanywhere.sdk.data.database.dao

import androidx.room.*
import com.runanywhere.sdk.data.database.entities.AuthTokenEntity

/**
 * Auth Token DAO
 * Room DAO for authentication token data following iOS patterns
 */
@Dao
interface AuthTokenDao {

    @Query("SELECT * FROM auth_tokens WHERE id = :tokenId")
    suspend fun getTokenById(tokenId: String): AuthTokenEntity?

    @Query("SELECT * FROM auth_tokens ORDER BY updated_at DESC LIMIT 1")
    suspend fun getCurrentToken(): AuthTokenEntity?

    @Query("SELECT * FROM auth_tokens WHERE expires_at > :currentTime ORDER BY updated_at DESC LIMIT 1")
    suspend fun getValidToken(currentTime: Long = System.currentTimeMillis()): AuthTokenEntity?

    @Query("SELECT * FROM auth_tokens")
    suspend fun getAllTokens(): List<AuthTokenEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertToken(token: AuthTokenEntity)

    @Update
    suspend fun updateToken(token: AuthTokenEntity)

    @Delete
    suspend fun deleteToken(token: AuthTokenEntity)

    @Query("DELETE FROM auth_tokens WHERE id = :tokenId")
    suspend fun deleteTokenById(tokenId: String)

    @Query("DELETE FROM auth_tokens")
    suspend fun deleteAllTokens()

    @Query("DELETE FROM auth_tokens WHERE expires_at < :currentTime")
    suspend fun deleteExpiredTokens(currentTime: Long = System.currentTimeMillis())

    @Query("SELECT COUNT(*) FROM auth_tokens")
    suspend fun getTokenCount(): Int

    @Query("SELECT COUNT(*) FROM auth_tokens WHERE expires_at > :currentTime")
    suspend fun getValidTokenCount(currentTime: Long = System.currentTimeMillis()): Int
}
