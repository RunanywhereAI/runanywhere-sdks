package com.runanywhere.sdk.network

/**
 * Interface for checking network availability
 * Extracted from APIClient.kt for use by NetworkServiceFactory
 */
interface NetworkChecker {
    suspend fun isNetworkAvailable(): Boolean

    suspend fun getNetworkType(): String
}
