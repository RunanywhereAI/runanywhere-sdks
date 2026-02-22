package com.runanywhere.runanywhereai.domain.services

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener

// MARK: - Document Type

/**
 * Supported document types for RAG ingestion.
 * Mirrors iOS DocumentType exactly.
 */
enum class DocumentType {
    PDF,
    JSON,
    UNSUPPORTED;

    companion object {
        /**
         * Determine document type from a display name or file extension.
         * Mirrors iOS `DocumentType.init(url:)`.
         */
        fun from(fileName: String): DocumentType {
            return when (fileName.substringAfterLast('.', "").lowercase()) {
                "pdf" -> PDF
                "json" -> JSON
                else -> UNSUPPORTED
            }
        }
    }
}

// MARK: - Document Service Error

/**
 * Errors thrown by DocumentService.
 * Mirrors iOS DocumentServiceError exactly.
 */
sealed class DocumentServiceError(override val message: String) : Exception(message) {
    /** The file format is not supported (only PDF and JSON). */
    data class UnsupportedFormat(val ext: String) : DocumentServiceError(
        "Unsupported document format: .$ext. Only PDF and JSON files are supported.",
    )

    /** The PDF could not be parsed (corrupted, image-only, etc.). */
    data object PdfExtractionFailed : DocumentServiceError(
        "Failed to extract text from the PDF. The file may be corrupted or image-only.",
    )

    /** The JSON could not be parsed. */
    data class JsonExtractionFailed(val reason: String) : DocumentServiceError(
        "Failed to parse JSON file: $reason",
    )

    /** The file could not be read from the content URI. */
    data class FileReadFailed(val reason: String) : DocumentServiceError(
        "Failed to read file: $reason",
    )
}

// MARK: - Document Service

/**
 * Utility for extracting plain text from PDF and JSON files.
 *
 * Used to prepare document content for RAG ingestion. Takes Android Context
 * and content URI (Android equivalent of iOS security-scoped URL).
 *
 * Mirrors iOS DocumentService (static struct) exactly.
 */
object DocumentService {

    /**
     * Extract plain text from a file identified by a content URI.
     *
     * Supports PDF (via pdfbox-android) and JSON (via org.json).
     * Mirrors iOS `DocumentService.extractText(from:)`.
     *
     * @param context Android context for ContentResolver access
     * @param uri Content URI of the file (from a file picker or document provider)
     * @return Plain text content of the document
     * @throws DocumentServiceError for unsupported formats, extraction failures, or read errors
     */
    @Throws(DocumentServiceError::class)
    fun extractText(context: Context, uri: Uri): String {
        val fileName = getFileName(context, uri) ?: ""
        val documentType = DocumentType.from(fileName)

        return when (documentType) {
            DocumentType.PDF -> extractPdfText(context, uri)
            DocumentType.JSON -> extractJsonText(context, uri)
            DocumentType.UNSUPPORTED -> {
                val ext = fileName.substringAfterLast('.', "unknown")
                throw DocumentServiceError.UnsupportedFormat(ext)
            }
        }
    }

    // MARK: - Private Helpers

    private fun extractPdfText(context: Context, uri: Uri): String {
        // Initialize PDFBox Android resources (no-op if already initialized)
        PDFBoxResourceLoader.init(context.applicationContext)

        val inputStream = try {
            context.contentResolver.openInputStream(uri)
                ?: throw DocumentServiceError.PdfExtractionFailed
        } catch (e: DocumentServiceError) {
            throw e
        } catch (e: Exception) {
            throw DocumentServiceError.FileReadFailed(e.message ?: "Cannot open URI")
        }

        return inputStream.use { stream ->
            val document: PDDocument = try {
                PDDocument.load(stream)
            } catch (e: Exception) {
                throw DocumentServiceError.PdfExtractionFailed
            }

            document.use { doc ->
                if (doc.numberOfPages == 0) {
                    throw DocumentServiceError.PdfExtractionFailed
                }

                val stripper = PDFTextStripper()
                val text = try {
                    stripper.getText(doc)
                } catch (e: Exception) {
                    throw DocumentServiceError.PdfExtractionFailed
                }

                if (text.isBlank()) {
                    throw DocumentServiceError.PdfExtractionFailed
                }

                text.trim()
            }
        }
    }

    private fun extractJsonText(context: Context, uri: Uri): String {
        val raw = try {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                stream.bufferedReader().readText()
            } ?: throw DocumentServiceError.FileReadFailed("Cannot open URI")
        } catch (e: DocumentServiceError) {
            throw e
        } catch (e: Exception) {
            throw DocumentServiceError.FileReadFailed(e.message ?: "Read failed")
        }

        val parsed: Any = try {
            JSONTokener(raw).nextValue()
        } catch (e: JSONException) {
            throw DocumentServiceError.JsonExtractionFailed(e.message ?: "Invalid JSON")
        }

        val strings = mutableListOf<String>()
        extractStrings(parsed, strings)
        return strings.joinToString("\n")
    }

    /**
     * Recursively extract all string values from a parsed JSON object or array.
     * Mirrors iOS `DocumentService.extractStrings(from:into:)` exactly.
     */
    private fun extractStrings(value: Any, result: MutableList<String>) {
        when (value) {
            is String -> result.add(value)
            is JSONObject -> {
                val keys = value.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    extractStrings(value.get(key), result)
                }
            }
            is JSONArray -> {
                for (i in 0 until value.length()) {
                    extractStrings(value.get(i), result)
                }
            }
            // Numbers, booleans, and JSONObject.NULL are skipped (not text content)
        }
    }

    /**
     * Query the ContentResolver for the display name of a content URI.
     * Used to determine the document type from its file extension.
     */
    fun getFileName(context: Context, uri: Uri): String? {
        return context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) cursor.getString(nameIndex) else null
            } else {
                null
            }
        }
    }
}
