package com.runanywhere.runanywhereai.data.rag

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

data class ExtractedDocument(val name: String, val text: String)

// Pulls plain text out of a picked file for RAG ingestion. Supports PDF, JSON and any text/* file.
object DocumentExtractor {

    val acceptedMimeTypes = arrayOf("application/pdf", "application/json", "text/*")

    fun extract(context: Context, uri: Uri): ExtractedDocument {
        val name = displayName(context, uri) ?: "document"
        val text = when (name.substringAfterLast('.', "").lowercase()) {
            "pdf" -> extractPdf(context, uri)
            "json" -> extractJson(context, uri)
            else -> readText(context, uri)
        }
        require(text.isNotBlank()) { "No readable text found in $name." }
        return ExtractedDocument(name, text.trim())
    }

    private fun extractPdf(context: Context, uri: Uri): String {
        PDFBoxResourceLoader.init(context.applicationContext)
        val input = context.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Could not open the file.")
        return input.use { stream ->
            PDDocument.load(stream).use { doc ->
                check(doc.numberOfPages > 0) { "The PDF has no pages." }
                PDFTextStripper().getText(doc)
            }
        }
    }

    private fun extractJson(context: Context, uri: Uri): String {
        val strings = mutableListOf<String>()
        collectStrings(JSONTokener(readText(context, uri)).nextValue(), strings)
        return strings.joinToString("\n")
    }

    private fun collectStrings(value: Any?, out: MutableList<String>) {
        when (value) {
            is String -> out += value
            is JSONObject -> value.keys().forEach { collectStrings(value.get(it), out) }
            is JSONArray -> (0 until value.length()).forEach { collectStrings(value.get(it), out) }
        }
    }

    private fun readText(context: Context, uri: Uri): String =
        context.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() }
            ?: throw IllegalStateException("Could not read the file.")

    private fun displayName(context: Context, uri: Uri): String? =
        context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (cursor.moveToFirst() && index >= 0) cursor.getString(index)?.takeIf { it.isNotBlank() } else null
            }
}
