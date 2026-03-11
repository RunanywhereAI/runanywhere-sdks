package com.runanywhere.runanywhereai.data

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

/**
 * Errors thrown by [DocumentService].
 */
sealed class DocumentServiceError(override val message: String) : Exception(message) {
    data class UnsupportedFormat(val ext: String) : DocumentServiceError(
        "Unsupported format: .$ext. Only PDF and JSON are supported.",
    )

    data object PdfExtractionFailed : DocumentServiceError(
        "Failed to extract text from the PDF. The file may be corrupted or image-only.",
    )

    data class JsonExtractionFailed(val reason: String) : DocumentServiceError(
        "Failed to parse JSON file: $reason",
    )

    data class FileReadFailed(val reason: String) : DocumentServiceError(
        "Failed to read file: $reason",
    )
}

/**
 * Utility for extracting plain text from PDF and JSON files.
 * Used to prepare document content for RAG ingestion.
 */
object DocumentService {

    @Throws(DocumentServiceError::class)
    fun extractText(context: Context, uri: Uri): String {
        val fileName = getFileName(context, uri) ?: ""
        val ext = fileName.substringAfterLast('.', "").lowercase()

        return when (ext) {
            "pdf" -> extractPdfText(context, uri)
            "json" -> extractJsonText(context, uri)
            else -> throw DocumentServiceError.UnsupportedFormat(ext.ifEmpty { "unknown" })
        }
    }

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

    private fun extractPdfText(context: Context, uri: Uri): String {
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

    private fun extractStrings(value: Any, result: MutableList<String>) {
        when (value) {
            is String -> result.add(value)
            is JSONObject -> {
                val keys = value.keys()
                while (keys.hasNext()) {
                    extractStrings(value.get(keys.next()), result)
                }
            }
            is JSONArray -> {
                for (i in 0 until value.length()) {
                    extractStrings(value.get(i), result)
                }
            }
        }
    }
}
