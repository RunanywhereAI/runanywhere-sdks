package com.runanywhere.sdk.data.datasources

import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.network.services.AnalyticsNetworkService
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.time.Duration.Companion.seconds

/**
 * Remote data source for telemetry synchronization.
 * Matches Swift SDK's RemoteTelemetryDataSource actor
 *
 * Handles submission of telemetry batches to the production backend
 * with timeout, error handling, and retry logic.
 */
internal class RemoteTelemetryDataSource(
    private val analyticsNetworkService: AnalyticsNetworkService
) {
    private val logger = SDKLogger("RemoteTelemetryDataSource")

    /**
     * Submit batch to backend with timeout
     * Matches Swift SDK's submitBatch() method
     *
     * @param batch Telemetry batch to submit
     * @return Result indicating success or failure
     */
    suspend fun submitBatch(batch: TelemetryBatch): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            withTimeout(30.seconds) {
                logger.debug("Submitting telemetry batch with ${batch.events.size} events")

                analyticsNetworkService.submitTelemetryBatch(batch).getOrThrow()
                    .also { logger.info("✅ Successfully submitted telemetry batch") }
            }
        }
    }

    /**
     * Submit single event with timeout
     * Convenience method for single event submission
     *
     * @param event Telemetry event to submit
     * @return Result indicating success or failure
     */
    suspend fun submitEvent(event: TelemetryData): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            withTimeout(30.seconds) {
                logger.debug("Submitting single telemetry event: ${event.name}")

                analyticsNetworkService.submitTelemetryEvent(event).getOrThrow()
                    .also { logger.debug("✅ Successfully submitted telemetry event") }
            }
        }
    }
}
