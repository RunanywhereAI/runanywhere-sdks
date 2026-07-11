package com.runanywhere.runanywhereai.data.rag

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.charset.StandardCharsets

data class ExtractedDocument(val name: String, val text: String) {
    val metadataJSON: String
        get() = JSONObject()
            .put("source", name)
            .put("filename", name)
            .toString()
}

// Pulls plain text out of a picked file for RAG ingestion. Supports PDF, JSON and any text/* file.
object DocumentExtractor {

    val acceptedMimeTypes = arrayOf("application/pdf", "application/json", "text/*")
    internal const val MAX_SOURCE_BYTES = 10L * 1024 * 1024
    internal const val MAX_TEXT_CHARS = 1_000_000
    internal const val MAX_PDF_PAGES = 200
    private const val PDF_MAIN_MEMORY_BYTES = 4L * 1024 * 1024
    private const val PDF_SCRATCH_BYTES = 64L * 1024 * 1024

    fun extract(context: Context, uri: Uri): ExtractedDocument {
        val info = documentInfo(context, uri)
        val name = info.name ?: "document"
        require(info.size == null || info.size <= MAX_SOURCE_BYTES) {
            "The selected file is larger than the 10 MB document limit."
        }
        val text = when (name.substringAfterLast('.', "").lowercase()) {
            "pdf" -> extractPdf(context, uri)
            "json" -> extractJson(context, uri)
            else -> readText(context, uri)
        }
        require(text.isNotBlank()) { "No readable text found in $name." }
        return ExtractedDocument(name, enforceTextLimit(text).trim())
    }

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

    private fun extractJson(context: Context, uri: Uri): String {
        val strings = mutableListOf<String>()
        collectStrings(JSONTokener(readText(context, uri)).nextValue(), strings)
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

    private data class DocumentInfo(val name: String?, val size: Long?)

    private fun documentInfo(context: Context, uri: Uri): DocumentInfo =
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
            "The selected document exceeds the $MAX_TEXT_CHARS character text limit."
        }
        return text
    }

    private inline fun copyWithLimit(input: InputStream, write: (ByteArray, Int, Int) -> Unit) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            require(total <= MAX_SOURCE_BYTES) {
                "The selected file is larger than the 10 MB document limit."
            }
            write(buffer, 0, count)
        }
    }
}
