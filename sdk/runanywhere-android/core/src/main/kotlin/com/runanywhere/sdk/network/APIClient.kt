package com.runanywhere.sdk.network

import com.runanywhere.sdk.models.ModelInfo

/**
 * API client for RunAnywhere backend services
 */
interface APIClient {
    suspend fun authenticate(apiKey: String): AuthResult
    suspend fun getModels(): List<ModelInfo>
    suspend fun downloadModel(modelId: String): ByteArray
}

/**
 * Default implementation of APIClient
 */
class DefaultAPIClient : APIClient {
    override suspend fun authenticate(apiKey: String): AuthResult {
        // TODO: Implement actual authentication
        return AuthResult.Success("mock-token")
    }

    override suspend fun getModels(): List<ModelInfo> {
        // TODO: Implement actual model listing
        return emptyList()
    }

    override suspend fun downloadModel(modelId: String): ByteArray {
        // TODO: Implement actual model download
        return byteArrayOf()
    }
}

/**
 * Authentication result
 */
sealed class AuthResult {
    data class Success(val token: String) : AuthResult()
    data class Failure(val error: String) : AuthResult()
}
