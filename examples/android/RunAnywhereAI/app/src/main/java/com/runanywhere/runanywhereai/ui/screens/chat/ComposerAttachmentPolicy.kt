package com.runanywhere.runanywhereai.ui.screens.chat

import android.content.Context
import android.net.Uri
import com.runanywhere.runanywhereai.data.rag.DocumentExtractor
import java.util.Locale

/** The two things the composer can carry alongside a question. */
enum class ComposerAttachmentKind { IMAGE, DOCUMENT }

/** A file staged in the composer, resolved to a name the pill can show. */
data class StagedAttachment(
    val kind: ComposerAttachmentKind,
    val uri: Uri,
    val name: String,
)

/**
 * Whether a file can be attached, decided before it is staged.
 *
 * The system pickers already narrow what a user can choose — the Photo Picker returns images and
 * `OpenDocument` is given a MIME filter — but that is a convenience, not a guarantee: a document
 * provider can hand back a type it never advertised, and the size limits are ours, not the
 * picker's. Without this check a 40 MB PDF is accepted cheerfully and then fails several seconds
 * later inside extraction, where the message reads as the model having gone wrong rather than the
 * file having been too big. Refusing at attach time puts the sentence next to the decision.
 *
 * Every limit here is the one the downstream path actually enforces: documents defer to
 * [DocumentExtractor], so the two can never disagree about the same file.
 *
 * Shared with the Vision screen, which stages images through the same funnel — one definition of
 * "can this file be attached" rather than two that drift.
 */
object ComposerAttachmentPolicy {

    /** Which mode a file belongs to, or null when neither can take it. */
    fun kindFor(context: Context, uri: Uri): ComposerAttachmentKind? =
        kindFor(
            mimeType = context.contentResolver.getType(uri),
            displayName = DocumentExtractor.documentInfo(context, uri).name,
        )

    /**
     * The same decision from facts already read.
     *
     * MIME first, filename second: providers routinely hand over Markdown as
     * `application/octet-stream`, and a strict MIME check would reject a file the ingest path
     * reads perfectly well. Taking the two facts as parameters lets [reasonToReject] resolve a
     * kind *and* a size from a single provider query instead of three.
     */
    internal fun kindFor(mimeType: String?, displayName: String?): ComposerAttachmentKind? {
        val mime = mimeType?.lowercase(Locale.US)
        if (mime != null && mime.startsWith("image/")) return ComposerAttachmentKind.IMAGE
        if (mime != null && (mime.startsWith("text/") || mime in DOCUMENT_MIME_TYPES)) {
            return ComposerAttachmentKind.DOCUMENT
        }
        val name = displayName?.lowercase(Locale.US) ?: return null
        if (IMAGE_EXTENSIONS.any(name::endsWith)) return ComposerAttachmentKind.IMAGE
        if (DOCUMENT_EXTENSIONS.any(name::endsWith)) return ComposerAttachmentKind.DOCUMENT
        return null
    }

    /** A sentence explaining why [uri] cannot be attached as [kind], or null when it can. */
    fun reasonToReject(context: Context, kind: ComposerAttachmentKind, uri: Uri): String? {
        val info = DocumentExtractor.documentInfo(context, uri)
        if (info.size == 0L) return "That file is empty."

        // A type *neither* mode recognises used to fall straight through as acceptable, because
        // only a positively-mismatched kind was refused. Such a file was staged, sent, and then
        // failed seconds later inside extraction — the one place where the message reads as the
        // model's fault. Anything we cannot name is refused here instead.
        if (kindFor(context.contentResolver.getType(uri), info.name) != kind) {
            return unsupportedTypeReason(kind)
        }

        val limit = when (kind) {
            ComposerAttachmentKind.IMAGE -> MAX_IMAGE_BYTES
            ComposerAttachmentKind.DOCUMENT -> DocumentExtractor.MAX_SOURCE_BYTES
        }
        // A provider that reports no size gets the benefit of the doubt; the extraction path
        // enforces the same ceiling again while streaming, so nothing oversized slips through.
        if (info.size != null && info.size > limit) {
            val noun = if (kind == ComposerAttachmentKind.IMAGE) "Images" else "Documents"
            return "$noun must be ${limit / BYTES_PER_MB} MB or smaller."
        }
        return null
    }

    /** The display name a provider reports, or a generic stand-in scoped to the mode. */
    fun displayName(context: Context, kind: ComposerAttachmentKind, uri: Uri): String =
        DocumentExtractor.documentInfo(context, uri).name
            ?: if (kind == ComposerAttachmentKind.IMAGE) "Selected image" else "Selected document"

    private fun unsupportedTypeReason(kind: ComposerAttachmentKind): String = when (kind) {
        ComposerAttachmentKind.IMAGE -> "That is not an image. Attach a PNG, JPEG, WebP, HEIC, or GIF."
        ComposerAttachmentKind.DOCUMENT ->
            "That file type is not supported. Attach a PDF, JSON, or plain-text file."
    }

    /**
     * Images are decoded and downscaled before they reach the model, so the ceiling only has to
     * keep a single decode off the heap rather than match any model input size.
     */
    private const val MAX_IMAGE_BYTES = 12L * 1024 * 1024

    private const val BYTES_PER_MB = 1024 * 1024

    private val DOCUMENT_MIME_TYPES = listOf("application/pdf", "application/json")
    private val DOCUMENT_EXTENSIONS = listOf(".pdf", ".json", ".txt", ".md", ".markdown", ".csv")

    /**
     * The filename fallback for images, which the extension check used to lack entirely. It is
     * needed for the same reason the document list is: a provider that reports a PNG as
     * `application/octet-stream` would otherwise be told its own photo is not an image.
     */
    private val IMAGE_EXTENSIONS =
        listOf(".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".heic", ".heif")
}
