package com.runanywhereaI

import android.net.Uri
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class DocumentServiceModule(private val reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String = "DocumentService"

    override fun initialize() {
        super.initialize()
        PDFBoxResourceLoader.init(reactContext)
    }

    @ReactMethod
    fun extractText(filePath: String, promise: Promise) {
        Thread {
            try {
                val fileType = resolveFileType(filePath)
                val text = when (fileType) {
                    FileType.PDF -> extractPDFText(filePath)
                    FileType.JSON -> extractJSONText(filePath)
                    FileType.PLAIN_TEXT -> readPlainText(filePath)
                }
                promise.resolve(text)
            } catch (e: Exception) {
                promise.reject("EXTRACT_ERROR", e.localizedMessage, e)
            }
        }.start()
    }

    private enum class FileType { PDF, JSON, PLAIN_TEXT }

    private fun resolveFileType(filePath: String): FileType {
        // For content:// URIs, use the content resolver to get the MIME type
        if (filePath.startsWith("content://")) {
            val mimeType = reactContext.contentResolver.getType(Uri.parse(filePath))
            if (mimeType != null) {
                return when {
                    mimeType == "application/pdf" -> FileType.PDF
                    mimeType == "application/json" -> FileType.JSON
                    else -> FileType.PLAIN_TEXT
                }
            }
        }

        // Fall back to extension-based detection for file:// and raw paths
        val ext = filePath.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "pdf" -> FileType.PDF
            "json" -> FileType.JSON
            else -> FileType.PLAIN_TEXT
        }
    }

    private fun extractPDFText(filePath: String): String {
        val inputStream = openInputStream(filePath)
            ?: throw Exception("Failed to open PDF. File may be corrupted or image-only.")

        val document = inputStream.use { PDDocument.load(it) }
        document.use { doc ->
            if (doc.numberOfPages == 0) {
                throw Exception("PDF has no pages.")
            }
            val stripper = PDFTextStripper()
            val result = stripper.getText(doc).trim()
            if (result.isEmpty()) {
                throw Exception("PDF contains no extractable text (may be image-only).")
            }
            return result
        }
    }

    private fun extractJSONText(filePath: String): String {
        val raw = readPlainText(filePath)
        val parsed = when {
            raw.trimStart().startsWith("[") -> JSONArray(raw) as Any
            else -> JSONObject(raw) as Any
        }
        val strings = mutableListOf<String>()
        extractStrings(parsed, strings)
        return strings.joinToString("\n")
    }

    private fun extractStrings(value: Any, result: MutableList<String>) {
        when (value) {
            is String -> result.add(value)
            is JSONObject -> {
                for (key in value.keys()) {
                    extractStrings(value.get(key), result)
                }
            }
            is JSONArray -> {
                for (i in 0 until value.length()) {
                    extractStrings(value.get(i), result)
                }
            }
        }
    }

    private fun readPlainText(filePath: String): String {
        val inputStream = openInputStream(filePath)
            ?: throw Exception("Failed to open file at: $filePath")
        return inputStream.use { it.bufferedReader().readText() }
    }

    private fun openInputStream(filePath: String): java.io.InputStream? {
        return if (filePath.startsWith("content://")) {
            reactContext.contentResolver.openInputStream(Uri.parse(filePath))
        } else {
            val path = if (filePath.startsWith("file://")) {
                Uri.parse(filePath).path ?: filePath.removePrefix("file://")
            } else {
                filePath
            }
            File(path).inputStream()
        }
    }
}
