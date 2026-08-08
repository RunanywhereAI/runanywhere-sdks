package com.runanywhere.runanywhereai.data.rag

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.charset.StandardCharsets
import java.util.Locale

data class ExtractedDocument(val name: String, val text: String) {
    val metadata: Map<String, String>
        get() = mapOf("source" to name, "filename" to name)
}

// Pulls plain text out of a picked file for RAG ingestion. Supports PDF, JSON and any text/* file.
object DocumentExtractor {

    val acceptedMimeTypes = arrayOf("application/pdf", "application/json", "text/*")
    internal const val MAX_SOURCE_BYTES = 10L * 1024 * 1024
    internal const val MAX_TEXT_CHARS = 1_000_000
    internal const val MAX_PDF_PAGES = 200
    private const val PDF_MAIN_MEMORY_BYTES = 4L * 1024 * 1024
    private const val PDF_SCRATCH_BYTES = 64L * 1024 * 1024
    private const val BYTES_PER_MB = 1024 * 1024

    fun extract(context: Context, uri: Uri): ExtractedDocument {
        val info = documentInfo(context, uri)
        val name = info.name ?: "document"
        require(info.size == null || info.size <= MAX_SOURCE_BYTES) { sourceTooLargeMessage() }
        val text = when (formatOf(context, uri, name)) {
            DocumentFormat.PDF -> extractPdf(context, uri)
            DocumentFormat.JSON -> extractJson(context, uri, name)
            DocumentFormat.TEXT -> readText(context, uri)
        }
        require(text.isNotBlank()) { "No readable text found in $name." }
        return ExtractedDocument(name, enforceTextLimit(text).trim())
    }

    /** How the bytes behind a URI have to be read to get text out of them. */
    private enum class DocumentFormat { PDF, JSON, TEXT }

    /**
     * Declared type first, filename second, magic bytes last.
     *
     * Dispatching on the extension alone sent every provider that reports a name without one — a
     * scanner app's "Document", a share-sheet temp file, a Drive export — down the plain-text
     * path, so a PDF reached the model as its own binary header decoded as UTF-8. The provider's
     * declared MIME type survives a missing extension, and the `%PDF-` signature survives both
     * being wrong.
     */
    private fun formatOf(context: Context, uri: Uri, name: String): DocumentFormat {
        val mime = context.contentResolver.getType(uri)?.lowercase(Locale.US)
        val extension = name.substringAfterLast('.', "").lowercase(Locale.US)
        return when {
            mime == "application/pdf" || extension == "pdf" -> DocumentFormat.PDF
            mime == "application/json" || extension == "json" -> DocumentFormat.JSON
            looksLikePdf(context, uri) -> DocumentFormat.PDF
            else -> DocumentFormat.TEXT
        }
    }

    /** True when the stream opens with the PDF signature, whatever the provider claims. */
    private fun looksLikePdf(context: Context, uri: Uri): Boolean =
        runCatching {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                val header = ByteArray(PDF_SIGNATURE.size)
                stream.read(header) == header.size && header.contentEquals(PDF_SIGNATURE)
            } ?: false
        }.getOrDefault(false)

    private val PDF_SIGNATURE = "%PDF-".toByteArray(StandardCharsets.US_ASCII)

    private fun extractPdf(context: Context, uri: Uri): String {
        PDFBoxResourceLoader.init(context.applicationContext)
        val input = context.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Could not open the file.")
        val temp = File.createTempFile("rag-document-", ".pdf", context.cacheDir)
        try {
            input.use { source ->
                temp.outputStream().use { destination -> copyWithLimit(source, destination::write) }
            }
            val memory = MemoryUsageSetting.setupMixed(PDF_MAIN_MEMORY_BYTES, PDF_SCRATCH_BYTES)
                .setTempDir(context.cacheDir)
            return PDDocument.load(temp, memory).use { doc ->
                check(doc.numberOfPages > 0) { "The PDF has no pages." }
                require(doc.numberOfPages <= MAX_PDF_PAGES) {
                    "The selected PDF exceeds the $MAX_PDF_PAGES page limit."
                }
                enforceTextLimit(PDFTextStripper().getText(doc))
            }
        } finally {
            temp.delete()
        }
    }

    private fun extractJson(context: Context, uri: Uri, name: String): String {
        val parsed = try {
            JSONTokener(readText(context, uri)).nextValue()
        } catch (e: JSONException) {
            // The tokener reports a character offset ("Unterminated object at character 412"),
            // which tells the reader nothing they can act on. Name the file instead — the remedy
            // is to pick a different one, not to count bytes.
            throw IllegalArgumentException("$name is not valid JSON.", e)
        }
        val strings = mutableListOf<String>()
        collectStrings(parsed, strings)
        return enforceTextLimit(strings.joinToString("\n"))
    }

    private fun collectStrings(value: Any?, out: MutableList<String>) {
        when (value) {
            is String -> out += value
            is JSONObject -> value.keys().forEach { collectStrings(value.get(it), out) }
            is JSONArray -> (0 until value.length()).forEach { collectStrings(value.get(it), out) }
        }
    }

    private fun readText(context: Context, uri: Uri): String =
        context.contentResolver.openInputStream(uri)?.use(::readUtf8TextWithinLimits)
            ?: throw IllegalStateException("Could not read the file.")

    /** Display name and byte size as the provider reports them; either may be absent. */
    data class DocumentInfo(val name: String?, val size: Long?)

    /**
     * Internal rather than private so the composer can pre-flight a file with the same reader that
     * will later ingest it. Checking the size at attach time and again at extraction time using two
     * different queries is how the two ends of a flow drift into disagreeing about the same file.
     */
    internal fun documentInfo(context: Context, uri: Uri): DocumentInfo =
        context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (!cursor.moveToFirst()) return@use DocumentInfo(null, null)
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                DocumentInfo(
                    name = nameIndex.takeIf { it >= 0 }?.let(cursor::getString)?.takeIf { it.isNotBlank() },
                    size = sizeIndex.takeIf { it >= 0 && !cursor.isNull(it) }
                        ?.let(cursor::getLong)
                        ?.takeIf { it >= 0 },
                )
            }
            ?: DocumentInfo(null, null)

    internal fun readUtf8TextWithinLimits(input: InputStream): String {
        val output = ByteArrayOutputStream()
        copyWithLimit(input, output::write)
        return enforceTextLimit(output.toString(StandardCharsets.UTF_8.name()))
    }

    internal fun enforceTextLimit(text: String): String {
        require(text.length <= MAX_TEXT_CHARS) {
            "That document holds more text than this app can index " +
                "(over ${MAX_TEXT_CHARS / THOUSAND}k characters)."
        }
        return text
    }

    private fun sourceTooLargeMessage(): String =
        "That file is larger than the ${MAX_SOURCE_BYTES / BYTES_PER_MB} MB document limit."

    private const val THOUSAND = 1_000

    private inline fun copyWithLimit(input: InputStream, write: (ByteArray, Int, Int) -> Unit) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            require(total <= MAX_SOURCE_BYTES) { sourceTooLargeMessage() }
            write(buffer, 0, count)
        }
    }
}
