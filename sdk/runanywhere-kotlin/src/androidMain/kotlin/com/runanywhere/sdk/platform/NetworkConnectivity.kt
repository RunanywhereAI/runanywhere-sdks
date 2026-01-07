/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Network connectivity checker for Android.
 */

package com.runanywhere.sdk.platform

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.runanywhere.sdk.storage.AndroidPlatformContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Network connectivity status.
 */
enum class NetworkStatus {
    /** Network is available */
    AVAILABLE,
    /** Network is unavailable (no connection) */
    UNAVAILABLE,
    /** Network status is unknown */
    UNKNOWN
}

/**
 * Network type information.
 */
enum class NetworkType {
    /** WiFi connection */
    WIFI,
    /** Cellular/mobile data connection */
    CELLULAR,
    /** Ethernet connection */
    ETHERNET,
    /** VPN connection */
    VPN,
    /** Other or unknown connection type */
    OTHER,
    /** No connection */
    NONE
}

/**
 * Network connectivity checker for Android.
 *
 * Provides methods to check current network status and observe connectivity changes.
 * Uses Android's ConnectivityManager for accurate network state detection.
 */
object NetworkConnectivity {

    private const val TAG = "NetworkConnectivity"

    private val _networkStatus = MutableStateFlow(NetworkStatus.UNKNOWN)

    /** Observable network status flow */
    val networkStatus: StateFlow<NetworkStatus> = _networkStatus.asStateFlow()

    private val _networkType = MutableStateFlow(NetworkType.NONE)

    /** Observable network type flow */
    val networkType: StateFlow<NetworkType> = _networkType.asStateFlow()

    @Volatile
    private var isMonitoring = false

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    /**
     * Check if network is currently available.
     *
     * This performs a synchronous check of the current network state.
     *
     * @return true if network is available, false otherwise
     */
    fun isNetworkAvailable(): Boolean {
        return try {
            if (!AndroidPlatformContext.isInitialized()) {
                // If context not initialized, assume network is available
                // (will fail later with proper error if not)
                return true
            }

            val context = AndroidPlatformContext.applicationContext
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return true // Assume available if can't get manager

            val network = connectivityManager.activeNetwork ?: return false
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false

            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (e: Exception) {
            // If we can't check, assume available (will fail with network error if not)
            true
        }
    }

    /**
     * Get the current network type.
     *
     * @return The current network type
     */
    fun getCurrentNetworkType(): NetworkType {
        return try {
            if (!AndroidPlatformContext.isInitialized()) {
                return NetworkType.OTHER
            }

            val context = AndroidPlatformContext.applicationContext
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return NetworkType.OTHER

            val network = connectivityManager.activeNetwork ?: return NetworkType.NONE
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return NetworkType.NONE

            when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> NetworkType.WIFI
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> NetworkType.CELLULAR
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> NetworkType.ETHERNET
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> NetworkType.VPN
                else -> NetworkType.OTHER
            }
        } catch (e: Exception) {
            NetworkType.OTHER
        }
    }

    /**
     * Start monitoring network connectivity changes.
     *
     * Call this during SDK initialization to enable real-time network status updates.
     */
    fun startMonitoring() {
        if (isMonitoring) return

        try {
            if (!AndroidPlatformContext.isInitialized()) {
                return
            }

            val context = AndroidPlatformContext.applicationContext
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return

            val networkRequest = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    _networkStatus.value = NetworkStatus.AVAILABLE
                    updateNetworkType()
                }

                override fun onLost(network: Network) {
                    _networkStatus.value = NetworkStatus.UNAVAILABLE
                    _networkType.value = NetworkType.NONE
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities
                ) {
                    val hasInternet = networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    val validated = networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)

                    _networkStatus.value = if (hasInternet && validated) {
                        NetworkStatus.AVAILABLE
                    } else {
                        NetworkStatus.UNAVAILABLE
                    }

                    updateNetworkType()
                }

                override fun onUnavailable() {
                    _networkStatus.value = NetworkStatus.UNAVAILABLE
                    _networkType.value = NetworkType.NONE
                }
            }

            connectivityManager.registerNetworkCallback(networkRequest, networkCallback!!)
            isMonitoring = true

            // Set initial state
            _networkStatus.value = if (isNetworkAvailable()) NetworkStatus.AVAILABLE else NetworkStatus.UNAVAILABLE
            _networkType.value = getCurrentNetworkType()

        } catch (e: Exception) {
            // Silently fail - network monitoring is optional
        }
    }

    /**
     * Stop monitoring network connectivity changes.
     *
     * Call this during SDK shutdown to clean up resources.
     */
    fun stopMonitoring() {
        if (!isMonitoring) return

        try {
            if (!AndroidPlatformContext.isInitialized()) {
                return
            }

            val context = AndroidPlatformContext.applicationContext
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return

            networkCallback?.let {
                connectivityManager.unregisterNetworkCallback(it)
            }
            networkCallback = null
            isMonitoring = false

        } catch (e: Exception) {
            // Silently fail
        }
    }

    private fun updateNetworkType() {
        _networkType.value = getCurrentNetworkType()
    }

    /**
     * Get a human-readable description of the current network status.
     *
     * @return A string describing the current network state
     */
    fun getNetworkDescription(): String {
        val status = if (isNetworkAvailable()) "Connected" else "Disconnected"
        val type = getCurrentNetworkType().name.lowercase().replaceFirstChar { it.uppercase() }
        return "$status ($type)"
    }
}
