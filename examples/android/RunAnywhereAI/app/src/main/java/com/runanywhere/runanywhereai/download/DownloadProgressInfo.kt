package com.runanywhere.runanywhereai.download

import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.ErrorCode
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.api.DownloadEvent
import java.util.Locale

/**
 * What one SDK event means for a transfer somebody is watching.
 *
 * `RunAnywhere.models.download(...)` reports a failure as a terminal [DownloadEvent.Failed] and then
 * ends the flow normally — it never throws. A collector that only pattern-matches the events it can
 * draw therefore sees a failed download as a flow that simply finished, which is indistinguishable
 * from success: the notification said "is ready" for a model that was not on disk. Making the fold
 * return an outcome instead of a nullable frame means every caller has to answer the question.
 */
sealed interface DownloadUpdate {
    /** New numbers to show. */
    data class Advanced(val info: DownloadProgressInfo) : DownloadUpdate

    /** A marker with nothing on it a reader would see — the opening event, mostly. */
    data object Ignored : DownloadUpdate

    /** Every byte is on disk and the model is registered. */
    data object Finished : DownloadUpdate

    /**
     * The transfer ended with the model still incomplete.
     *
     * [cancelled] separates the user's own stop from a fault. They look identical in the data —
     * bytes on disk, nothing running — but they are opposite events to a reader, and offering
     * "Retry" in error red for something the user deliberately stopped reads as the app having lost
     * track of what happened.
     */
    data class Stopped(val message: String, val cancelled: Boolean) : DownloadUpdate
}

/**
 * Which part of "downloading a model" is running.
 *
 * The bytes arriving is only the first of three, and the other two are not instant on a
 * multi-gigabyte bundle. Without naming them the bar parks near the end with the last measured rate
 * still on screen, which is indistinguishable from a stalled connection.
 */
enum class DownloadPhase { TRANSFERRING, VERIFYING, EXTRACTING }

/**
 * What a download looks like to the UI at one instant.
 *
 * A model is hundreds of megabytes to several gigabytes, so a bare percentage is not enough to tell
 * a slow transfer from a stalled one — the number a user actually wants is how fast it is going and
 * how long is left. Every field here comes from [DownloadEvent.Progress], which the SDK fills from
 * what C++ already measures; nothing is re-derived from successive byte counts, because a rate
 * computed from two UI-thread samples disagrees with the transfer that knows its own history.
 *
 * Optional fields are null when genuinely unknown rather than zero, so the UI can omit a row instead
 * of showing "0 B/s" while the connection is still opening.
 */
data class DownloadProgressInfo(
    val bytesDone: Long = 0,
    val bytesTotal: Long = 0,
    val bytesPerSecond: Float? = null,
    val etaSeconds: Long? = null,
    val retryAttempt: Int = 0,
    val currentFileIndex: Int = 0,
    val totalFiles: Int = 1,
    /** 0.0..1.0, or null when the total size is unknown and the bar must be indeterminate. */
    val fraction: Float? = null,
    /** Which part of the operation is running. See [DownloadPhase]. */
    val phase: DownloadPhase = DownloadPhase.TRANSFERRING,
) {
    val percent: Int? get() = fraction?.let { (it * 100).toInt().coerceIn(0, 100) }

    /** True when the size is unknown, so the caller shows an indeterminate bar. */
    val isIndeterminate: Boolean get() = fraction == null

    /**
     * "1.2 GB of 4.1 GB", or just the transferred amount when the total is unknown — and blank
     * before the first byte lands, so the caller can say "Starting…" instead of "0 B", which reads
     * like a transfer that is already stuck.
     */
    val bytesLabel: String
        get() = when {
            bytesTotal > 0 -> "${formatBytes(bytesDone)} of ${formatBytes(bytesTotal)}"
            bytesDone > 0 -> formatBytes(bytesDone)
            else -> ""
        }

    /** "3.4 MB/s", or null when no rate has been measured yet. */
    val speedLabel: String? get() = bytesPerSecond?.let { "${formatBytes(it.toLong())}/s" }

    /**
     * "456 MB already downloaded" — what a stopped transfer left behind.
     *
     * The reasonable fear with a half-finished multi-gigabyte download is that continuing means
     * paying for it twice. Naming the amount is the only thing that answers it; "resumes where it
     * stopped" is a promise, this is the evidence.
     */
    val keptLabel: String? get() = formatBytes(bytesDone).takeIf { bytesDone > 0 }

    /** "2m 15s left", or null when there is nothing trustworthy to project. */
    val etaLabel: String? get() = etaSeconds?.takeIf { it > 0 }?.let { "${formatDuration(it)} left" }

    /** "File 2 of 3" for a multi-file model, null for the ordinary single-file case. */
    val fileCountLabel: String?
        get() = if (totalFiles > 1) "File ${currentFileIndex + 1} of $totalFiles" else null

    /** "Retry 2" once the transfer has recovered at least once, so a retry is never silent. */
    val retryLabel: String? get() = retryAttempt.takeIf { it > 0 }?.let { "Retry $it" }

    /**
     * The single line of detail under the progress bar.
     *
     * Ordered by what a waiting user looks for first — how much is left, then how fast, then when it
     * will be done — and joined only from the parts that are actually known, so an early frame reads
     * "12 MB of 4.1 GB" rather than "12 MB of 4.1 GB · 0 B/s · 0s left".
     *
     * The post-transfer phases replace the line outright rather than adding to it: checksumming a
     * multi-gigabyte bundle takes real seconds, and leaving the last measured rate on screen while
     * no bytes are moving is the difference between "nearly done" and "frozen at 99%".
     */
    val detailLine: String
        get() = when (phase) {
            DownloadPhase.VERIFYING -> "Checking the download…"
            DownloadPhase.EXTRACTING -> "Unpacking…"
            DownloadPhase.TRANSFERRING ->
                listOfNotNull(
                    bytesLabel.takeIf { it.isNotEmpty() },
                    speedLabel,
                    etaLabel,
                    fileCountLabel,
                    retryLabel,
                ).joinToString(" · ")
        }

    companion object {
        /**
         * Fold one SDK event into the running view of the transfer.
         *
         * Shared by every collector so a download looks the same wherever it is watched from —
         * the foreground service's notification and the picker row used to each have their own
         * `when`, and only one of them would ever have learned about a new phase.
         *
         * [latest] carries the bytes and file counts forward, because the post-transfer events
         * repeat none of them and a line that empties out mid-operation reads as a reset.
         */
        fun advance(latest: DownloadProgressInfo, event: DownloadEvent): DownloadUpdate =
            when (event) {
                is DownloadEvent.Progress -> DownloadUpdate.Advanced(from(event))
                // Every byte is on disk by the time these run, so the bar completes and the line
                // names the phase instead of leaving a rate behind that is no longer moving.
                is DownloadEvent.Verifying ->
                    DownloadUpdate.Advanced(latest.copy(fraction = 1f, phase = DownloadPhase.VERIFYING))
                // `percent` is deliberately ignored: the SDK does not pin its scale, and a bar
                // driven by a number that might be 0..1 or 0..100 is worse than one that is honest
                // about only knowing the phase.
                is DownloadEvent.Extracting ->
                    DownloadUpdate.Advanced(latest.copy(fraction = 1f, phase = DownloadPhase.EXTRACTING))
                is DownloadEvent.Completed -> DownloadUpdate.Finished
                // A cancel reaches Kotlin two ways: as coroutine cancellation when this process
                // stopped the transfer, and — when the native worker settles first — as a Failed
                // carrying ERROR_CODE_CANCELLED. Both are the user's own stop, so both must read
                // as paused rather than as a fault the app is blaming them for.
                is DownloadEvent.Failed -> DownloadUpdate.Stopped(
                    message = event.error.stoppedMessage(),
                    cancelled = event.error.code == ErrorCode.ERROR_CODE_CANCELLED,
                )
                is DownloadEvent.Cancelled -> DownloadUpdate.Stopped(
                    message = "Download stopped",
                    cancelled = true,
                )
                is DownloadEvent.Started -> DownloadUpdate.Ignored
            }

        fun from(event: DownloadEvent.Progress): DownloadProgressInfo = DownloadProgressInfo(
            bytesDone = event.bytesDone,
            bytesTotal = event.bytesTotal,
            bytesPerSecond = event.bytesPerSecond,
            etaSeconds = event.etaSeconds,
            retryAttempt = event.retryAttempt,
            currentFileIndex = event.currentFileIndex,
            totalFiles = event.totalFiles,
            fraction = event.fraction,
        )

        /**
         * The same view built from the raw proto, for the LoRA catalog — whose download verb still
         * takes a `DownloadProgress` callback rather than emitting [DownloadEvent].
         *
         * Applies the same missing-is-null normalisation the SDK's [DownloadEvent.Progress] mapping
         * does, so an adapter download and a model download read identically.
         */
        fun from(progress: DownloadProgress): DownloadProgressInfo {
            val total = progress.total_bytes
            return DownloadProgressInfo(
                bytesDone = progress.bytes_downloaded,
                bytesTotal = total,
                bytesPerSecond = progress.bytes_per_second.takeIf { it > 0f },
                etaSeconds = progress.eta_seconds,
                retryAttempt = progress.retry_attempt,
                currentFileIndex = progress.current_file_index,
                totalFiles = progress.total_files.coerceAtLeast(1),
                fraction = progress.overall_progress.takeIf { it > 0f },
            )
        }
    }
}

/**
 * The SDK's failure text, ready to be read by a person.
 *
 * It arrives as a bare fragment from wherever it was raised — "network error", "insufficient
 * storage" — and a lowercase fragment under a red icon reads like a log line that leaked into the
 * UI. The trailing stop is dropped so a caller can append to it without producing "..".
 */
fun String.asSentence(): String = trim().trimEnd('.').replaceFirstChar { it.uppercaseChar() }

/**
 * A sentence a reader can act on, for a transfer that stopped.
 *
 * The SDK's own message is preferred because it names the actual cause, but it is blank often
 * enough — a native worker that settles with no text — that a fallback is needed; "Download failed"
 * with no reason is still better than an empty error dialog.
 *
 * Normalised here rather than at each surface, because not every surface remembered to: the
 * Hugging Face sheet assigns this straight to its error banner, and showed the raw fragment
 * ("network error") the notification path had already learned to capitalise.
 */
private fun SDKException.stoppedMessage(): String =
    error.message.ifBlank { recoverySuggestion ?: "Download failed" }.asSentence()

/**
 * Binary-prefix size with one decimal above a megabyte.
 *
 * Decimals are dropped for KB and B: a byte count that precise changes several times a second and
 * reads as noise rather than information.
 */
private fun formatBytes(bytes: Long): String {
    val kb = 1024.0
    val mb = kb * 1024
    val gb = mb * 1024
    return when {
        bytes >= gb -> String.format(Locale.US, "%.1f GB", bytes / gb)
        bytes >= mb -> String.format(Locale.US, "%.1f MB", bytes / mb)
        bytes >= kb -> String.format(Locale.US, "%.0f KB", bytes / kb)
        else -> "$bytes B"
    }
}

/** Coarse duration — "45s", "2m 15s", "1h 20m". Seconds are dropped past an hour. */
private fun formatDuration(seconds: Long): String = when {
    seconds >= 3600 -> "${seconds / 3600}h ${(seconds % 3600) / 60}m"
    seconds >= 60 -> "${seconds / 60}m ${seconds % 60}s"
    else -> "${seconds}s"
}
