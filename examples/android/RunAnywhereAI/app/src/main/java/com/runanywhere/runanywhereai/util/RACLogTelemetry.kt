package com.runanywhere.runanywhereai.util

import ai.runanywhere.proto.v1.ErrorCode
import android.util.Log
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Events.publishSDKFailure
import java.util.ArrayDeque
import java.util.concurrent.CancellationException

/**
 * Bridges application warnings and errors into the SDK's canonical event and telemetry pipeline.
 *
 * The reporter is installed before app startup work begins. Until [markSDKInitialized] is called,
 * it retains only the most recent [MAX_PENDING_EVENTS] formatted diagnostics in memory. A successful
 * SDK initialization drains that queue immediately and in order; no timer, polling, or persisted
 * private-data buffer is involved. If initialization never succeeds, the process-local queue is
 * discarded with the process. A native publisher rejection leaves the diagnostic at the head of
 * the same bounded queue for an event-driven retry on the next warning/error or readiness signal.
 */
internal object RACLogTelemetry {
    private const val MAX_PENDING_EVENTS = 64

    private val reporter =
        RACLogTelemetryReporter(
            publisher = SDKFailurePublisher { event ->
                RunAnywhere.publishSDKFailure(
                    errorCode = event.errorCode,
                    message = event.message,
                    component = event.component,
                    operation = event.operation,
                    recoverable = event.recoverable,
                )
            },
            maxPendingEvents = MAX_PENDING_EVENTS,
        )

    fun install() {
        RACLog.errorReporter = reporter::report
    }

    fun markSDKInitialized() {
        reporter.markSDKInitialized()
    }
}

internal data class SDKFailureDiagnostic(
    val errorCode: Int,
    val message: String,
    val component: String,
    val operation: String,
    val recoverable: Boolean,
)

internal fun interface SDKFailurePublisher {
    fun publish(event: SDKFailureDiagnostic): Boolean
}

/** Thread-safe, bounded reporter kept separate from Android lifecycle code for focused tests. */
internal class RACLogTelemetryReporter(
    private val publisher: SDKFailurePublisher,
    private val maxPendingEvents: Int = 64,
) {
    private val lock = Any()
    private val pending = ArrayDeque<SDKFailureDiagnostic>(maxPendingEvents)
    private val isPublishing = ThreadLocal<Boolean>()

    private var sdkInitialized = false
    private var isDraining = false

    init {
        require(maxPendingEvents > 0) { "maxPendingEvents must be positive" }
    }

    fun report(
        priority: Int,
        tag: String,
        message: String,
        throwable: Throwable?,
    ) {
        if (priority < Log.WARN || isPublishing.get() == true) return

        val diagnostic = priority.toDiagnostic(tag, message, throwable)
        val shouldDrain =
            synchronized(lock) {
                enqueueBounded(diagnostic)
                if (sdkInitialized && !isDraining) {
                    isDraining = true
                    true
                } else {
                    false
                }
            }

        if (shouldDrain) drainPending()
    }

    fun markSDKInitialized() {
        val shouldDrain =
            synchronized(lock) {
                sdkInitialized = true
                if (pending.isNotEmpty() && !isDraining) {
                    isDraining = true
                    true
                } else {
                    false
                }
            }
        if (shouldDrain) drainPending()
    }

    private fun drainPending() {
        while (true) {
            val next =
                synchronized(lock) {
                    pending.pollFirst()
                        ?: run {
                            isDraining = false
                            return
                        }
                }
            if (!publishSafely(next)) {
                synchronized(lock) {
                    // Keep the rejected diagnostic for a later event-driven retry. Prefer it over
                    // newer entries if the bounded queue filled while the publisher was running.
                    if (pending.size == maxPendingEvents) pending.removeLast()
                    pending.addFirst(next)
                    isDraining = false
                }
                return
            }
        }
    }

    private fun enqueueBounded(diagnostic: SDKFailureDiagnostic) {
        if (pending.size == maxPendingEvents) pending.removeFirst()
        pending.addLast(diagnostic)
    }

    private fun publishSafely(diagnostic: SDKFailureDiagnostic): Boolean {
        if (isPublishing.get() == true) return false
        isPublishing.set(true)
        return try {
            publisher.publish(diagnostic)
        } catch (_: Throwable) {
            // Diagnostics must never crash the app or recursively report their own failure.
            false
        } finally {
            isPublishing.remove()
        }
    }

    private fun Int.toDiagnostic(
        tag: String,
        message: String,
        throwable: Throwable?,
    ): SDKFailureDiagnostic {
        val level = if (this >= Log.ERROR) "error" else "warning"
        return SDKFailureDiagnostic(
            errorCode = -ErrorCode.ERROR_CODE_PROCESSING_FAILED.value,
            message = formatMessage(tag, message, throwable),
            component = APP_COMPONENT,
            operation = "raclog.$level",
            recoverable = this < Log.ERROR,
        )
    }

    private fun formatMessage(
        tag: String,
        message: String,
        throwable: Throwable?,
    ): String = TelemetryDiagnosticPolicy.format(tag, message, throwable)

    private companion object {
        const val APP_COMPONENT = "app"
    }
}

/**
 * The only text boundary allowed to reach remote diagnostics from application logs.
 *
 * Raw messages, exception messages, stack traces, URLs, paths, model identifiers, and user
 * content are intentionally ignored. Only values from these finite allowlists are emitted, and
 * the final payload has a defensive length bound.
 */
internal object TelemetryDiagnosticPolicy {
    internal const val MAX_MESSAGE_CHARS = 96

    private val sourceCodes = mapOf(
        "ChatViewModel" to "chat",
        "CloudProviderRepository" to "cloud_provider",
        "ConversationRepository" to "conversation",
        "ConversationStore" to "conversation_store",
        "ModelBootstrap" to "model_bootstrap",
        "RagViewModel" to "rag",
        "RunAnywhereApplication" to "startup",
        "SettingsRepository" to "settings",
        "SettingsViewModel" to "settings",
        "SttViewModel" to "stt",
        "VadViewModel" to "vad",
        "VisionViewModel" to "vision",
        "VoiceViewModel" to "voice",
        "WebSearchTool" to "web_search",
    )
    private val eventCodes = setOf(
        "web_search_invalid_device_identity",
        "web_search_lite_fetch_failed",
        "web_search_lite_parser_no_results",
    )

    fun format(tag: String, message: String, throwable: Throwable?): String {
        val source = sourceCodes[tag] ?: "app"
        val event = message.takeIf(eventCodes::contains) ?: "operation_failed"
        val kind = when (throwable) {
            null -> "none"
            is CancellationException -> "cancelled"
            is SecurityException -> "security"
            is java.io.IOException -> "io"
            is IllegalArgumentException -> "invalid_input"
            is IllegalStateException -> "invalid_state"
            else -> "unexpected"
        }
        return "source=$source;event=$event;kind=$kind".take(MAX_MESSAGE_CHARS)
    }
}
