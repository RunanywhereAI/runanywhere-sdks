package com.runanywhere.runanywhereai.download

/**
 * Why a half-finished download is sitting there, from the reader's point of view.
 *
 * The two cases look identical in the data — bytes on disk, no transfer running — but they are
 * opposite events: one is a fault, one is the user's own decision. Colouring a deliberate cancel in
 * error red, or offering "Retry" for something that never failed, reads as the app having lost track
 * of what happened.
 */
enum class DownloadInterruption { FAILED, PAUSED }

/**
 * A stopped transfer as a screen needs it: what happened, why, and what survived.
 *
 * Derived here rather than in a composable so the reading of [ModelDownloadService.Interrupted] —
 * whether `cancelled` means "resumable pause", whether the failure text is fit to show, how the
 * retained bytes are worded — lives with the download layer that writes the record. The rows only
 * ever draw this; three list layouts previously each reached into the service record themselves,
 * and had already drifted about what a cancelled transfer meant.
 */
data class DownloadInterruptionState(
    val kind: DownloadInterruption,
    /**
     * The failure's own account of itself — "Insufficient storage", a server status — already a
     * sentence. Null for a pause, which needs no reason, and for a fault that carried no text.
     */
    val detail: String?,
    /** "456 MB", the amount a retry or resume will not have to fetch again. Null before the first byte. */
    val kept: String?,
) {
    /** True when a retry is the honest verb; false when the user stopped it themselves and may resume. */
    val isFailure: Boolean get() = kind == DownloadInterruption.FAILED
}

/**
 * How a row should read this record. One mapping, next to the type, so a new list layout cannot
 * invent a third reading of `cancelled`.
 */
fun ModelDownloadService.Interrupted.asState(): DownloadInterruptionState = DownloadInterruptionState(
    kind = if (cancelled) DownloadInterruption.PAUSED else DownloadInterruption.FAILED,
    detail = message?.takeIf { it.isNotBlank() }?.asSentence(),
    kept = progress?.keptLabel,
)
