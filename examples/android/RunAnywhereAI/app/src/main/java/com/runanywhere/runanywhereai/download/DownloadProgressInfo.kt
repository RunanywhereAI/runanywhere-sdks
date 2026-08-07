package com.runanywhere.runanywhereai.download

import ai.runanywhere.proto.v1.DownloadProgress
import com.runanywhere.sdk.public.api.DownloadEvent
import java.util.Locale

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
) {
    val percent: Int? get() = fraction?.let { (it * 100).toInt().coerceIn(0, 100) }

    /** True when the size is unknown, so the caller shows an indeterminate bar. */
    val isIndeterminate: Boolean get() = fraction == null

    /** "1.2 GB of 4.1 GB", or just the transferred amount when the total is unknown. */
    val bytesLabel: String
        get() = if (bytesTotal > 0) {
            "${formatBytes(bytesDone)} of ${formatBytes(bytesTotal)}"
        } else {
            formatBytes(bytesDone)
        }

    /** "3.4 MB/s", or null when no rate has been measured yet. */
    val speedLabel: String? get() = bytesPerSecond?.let { "${formatBytes(it.toLong())}/s" }

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
     */
    val detailLine: String
        get() = listOfNotNull(bytesLabel, speedLabel, etaLabel, fileCountLabel, retryLabel)
            .joinToString(" · ")

    companion object {
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
                fraction = progress.overall_progress.takeIf { it > 0f }
                    ?: total.takeIf { it > 0 }?.let {
                        (progress.bytes_downloaded.toFloat() / it).coerceIn(0f, 1f)
                    },
            )
        }
    }
}

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
