package com.runanywhere.sdk.services.download

import kotlinx.coroutines.channels.Channel

/**
 * JVM implementation - not implemented yet, focus is on Android
 */
internal actual suspend fun downloadWithPlatformImplementation(
    downloadURL: String,
    destinationPath: String,
    modelId: String,
    expectedSize: Long,
    progressChannel: Channel<DownloadProgress>
) {
    throw UnsupportedOperationException("JVM platform-specific download not implemented yet - focus is on Android")
}
