package com.runanywhere.runanywhereai.ui.chat.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.regex.Pattern

/**
 * Code syntax highlighter with support for multiple programming languages
 */
@Composable
fun CodeBlock(
    code: String,
    language: String? = null,
    modifier: Modifier = Modifier,
    showLineNumbers: Boolean = true,
    maxLines: Int? = null
) {
    val clipboardManager = LocalClipboardManager.current
    val detectedLanguage = language ?: detectLanguage(code)
    val highlightedCode = highlightCode(code, detectedLanguage)
    val codeLines = code.split('\n')
    
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
        ),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column {
            // Header with language and copy button
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = detectedLanguage.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold
                )
                
                IconButton(
                    onClick = {
                        clipboardManager.setText(AnnotatedString(code))
                    },
                    modifier = Modifier.size(32.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.ContentCopy,
                        contentDescription = "Copy code",
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            
            Divider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
            
            // Code content
            val displayLines = if (maxLines != null && codeLines.size > maxLines) {
                codeLines.take(maxLines)
            } else {
                codeLines
            }
            
            SelectionContainer {
                Row(
                    modifier = Modifier
                        .horizontalScroll(rememberScrollState())
                        .padding(12.dp)
                ) {
                    // Line numbers
                    if (showLineNumbers) {
                        Column(
                            modifier = Modifier.padding(end = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            displayLines.forEachIndexed { index, _ ->
                                Text(
                                    text = (index + 1).toString(),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                                    fontFamily = FontFamily.Monospace,
                                    textAlign = TextAlign.End,
                                    modifier = Modifier.widthIn(min = 24.dp)
                                )
                            }
                        }
                        
                        VerticalDivider(
                            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
                            modifier = Modifier.padding(end = 12.dp)
                        )
                    }
                    
                    // Code content
                    Column(
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        displayLines.forEach { line ->
                            Text(
                                text = highlightLine(line, detectedLanguage),
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace,
                                lineHeight = 18.sp
                            )
                        }
                    }
                }
            }
            
            // Show truncation indicator if needed
            if (maxLines != null && codeLines.size > maxLines) {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.7f)
                ) {
                    Text(
                        text = "... ${codeLines.size - maxLines} more lines",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(8.dp)
                    )
                }
            }
        }
    }
}

/**
 * Inline code highlighting for short code snippets
 */
@Composable
fun InlineCode(
    code: String,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(4.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
    ) {
        Text(
            text = code,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
        )
    }
}

/**
 * Detect programming language from code content
 */
private fun detectLanguage(code: String): String {
    val patterns = mapOf(
        "kotlin" to listOf(
            "fun\\s+\\w+\\s*\\(",
            "class\\s+\\w+",
            "val\\s+\\w+",
            "var\\s+\\w+",
            "import\\s+.*kotlin",
            "@Composable"
        ),
        "java" to listOf(
            "public\\s+class",
            "private\\s+static",
            "System\\.out\\.println",
            "import\\s+java\\.",
            "@Override"
        ),
        "python" to listOf(
            "def\\s+\\w+\\s*\\(",
            "import\\s+\\w+",
            "from\\s+\\w+\\s+import",
            "if\\s+__name__\\s*==\\s*['\"]__main__['\"]",
            "print\\s*\\("
        ),
        "javascript" to listOf(
            "function\\s+\\w+\\s*\\(",
            "const\\s+\\w+\\s*=",
            "let\\s+\\w+\\s*=",
            "var\\s+\\w+\\s*=",
            "console\\.log\\s*\\(",
            "=>\\s*\\{"
        ),
        "typescript" to listOf(
            "interface\\s+\\w+",
            "type\\s+\\w+\\s*=",
            ":\\s*string",
            ":\\s*number",
            "function\\s+\\w+\\s*\\(",
            "const\\s+\\w+:\\s*\\w+"
        ),
        "swift" to listOf(
            "func\\s+\\w+\\s*\\(",
            "var\\s+\\w+:\\s*\\w+",
            "let\\s+\\w+:\\s*\\w+",
            "import\\s+.*Swift",
            "@objc"
        ),
        "c" to listOf(
            "#include\\s*<.*>",
            "int\\s+main\\s*\\(",
            "printf\\s*\\(",
            "malloc\\s*\\(",
            "struct\\s+\\w+"
        ),
        "cpp" to listOf(
            "#include\\s*<iostream>",
            "std::",
            "class\\s+\\w+",
            "cout\\s*<<",
            "cin\\s*>>"
        ),
        "rust" to listOf(
            "fn\\s+\\w+\\s*\\(",
            "let\\s+mut\\s+\\w+",
            "match\\s+\\w+",
            "impl\\s+\\w+",
            "use\\s+.*::"
        ),
        "go" to listOf(
            "package\\s+\\w+",
            "import\\s+\\(",
            "func\\s+\\w+\\s*\\(",
            "fmt\\.Print",
            "go\\s+"
        ),
        "html" to listOf(
            "<html.*>",
            "<div.*>",
            "<p.*>",
            "<!DOCTYPE",
            "<script.*>"
        ),
        "css" to listOf(
            "\\{.*:.*\\}",
            "@media",
            "display:\\s*\\w+",
            "color:\\s*#?\\w+",
            "\\.[\\w-]+\\s*\\{"
        ),
        "sql" to listOf(
            "SELECT\\s+.*FROM",
            "INSERT\\s+INTO",
            "UPDATE\\s+.*SET",
            "DELETE\\s+FROM",
            "CREATE\\s+TABLE"
        ),
        "json" to listOf(
            "^\\s*\\{",
            "\"\\w+\"\\s*:",
            "\\[\\s*\\{",
            "\\}\\s*,?\\s*$"
        ),
        "xml" to listOf(
            "<\\?xml",
            "<\\w+.*>.*</\\w+>",
            "<\\w+.*/>",
            "xmlns:"
        ),
        "yaml" to listOf(
            "^\\s*\\w+:",
            "^\\s*-\\s+",
            "---",
            "\\|\\s*$"
        ),
        "markdown" to listOf(
            "^#{1,6}\\s+",
            "\\*\\*.*\\*\\*",
            "\\[.*\\]\\(.*\\)",
            "```\\w*",
            "^\\s*[*-]\\s+"
        ),
        "bash" to listOf(
            "#!/bin/bash",
            "#!/bin/sh",
            "\\$\\{.*\\}",
            "if\\s*\\[.*\\]",
            "echo\\s+"
        )
    )
    
    for ((language, languagePatterns) in patterns) {
        var matches = 0
        for (pattern in languagePatterns) {
            if (Pattern.compile(pattern, Pattern.CASE_INSENSITIVE).matcher(code).find()) {
                matches++
            }
        }
        if (matches >= 2) { // Require at least 2 pattern matches
            return language
        }
    }
    
    return "text" // Default to plain text
}

/**
 * Highlight code with syntax coloring
 */
private fun highlightCode(code: String, language: String): AnnotatedString {
    return buildAnnotatedString {
        append(code)
        // Apply basic syntax highlighting based on language
        applySyntaxHighlighting(this, code, language)
    }
}

/**
 * Highlight a single line of code
 */
private fun highlightLine(line: String, language: String): AnnotatedString {
    return buildAnnotatedString {
        append(line)
        applySyntaxHighlighting(this, line, language)
    }
}

/**
 * Apply syntax highlighting to an AnnotatedString.Builder
 */
private fun applySyntaxHighlighting(
    builder: AnnotatedString.Builder,
    text: String,
    language: String
) {
    when (language.lowercase()) {
        "kotlin", "java", "swift" -> applyOOPHighlighting(builder, text)
        "python" -> applyPythonHighlighting(builder, text)
        "javascript", "typescript" -> applyJavaScriptHighlighting(builder, text)
        "c", "cpp", "rust" -> applyCStyleHighlighting(builder, text)
        "html", "xml" -> applyMarkupHighlighting(builder, text)
        "css" -> applyCSSHighlighting(builder, text)
        "json" -> applyJSONHighlighting(builder, text)
        "sql" -> applySQLHighlighting(builder, text)
        "bash" -> applyBashHighlighting(builder, text)
        else -> applyGenericHighlighting(builder, text)
    }
}

/**
 * Highlighting for object-oriented languages (Kotlin, Java, Swift)
 */
private fun applyOOPHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Keywords
    val keywords = listOf(
        "class", "interface", "fun", "val", "var", "if", "else", "when", "for", "while",
        "return", "import", "package", "public", "private", "protected", "internal",
        "override", "abstract", "final", "static", "const", "let", "func", "struct",
        "enum", "extension", "protocol", "@Composable", "@Override"
    )
    
    applyPatternHighlighting(builder, text, keywords.joinToString("|") { "\\b$it\\b" }, colors.keyword)
    
    // Strings
    applyPatternHighlighting(builder, text, "\"([^\"\\\\]|\\\\.)*\"", colors.string)
    applyPatternHighlighting(builder, text, "'([^'\\\\]|\\\\.)*'", colors.string)
    
    // Numbers
    applyPatternHighlighting(builder, text, "\\b\\d+(\\.\\d+)?[fLdD]?\\b", colors.number)
    
    // Comments
    applyPatternHighlighting(builder, text, "//.*$", colors.comment)
    applyPatternHighlighting(builder, text, "/\\*.*?\\*/", colors.comment)
    
    // Annotations
    applyPatternHighlighting(builder, text, "@\\w+", colors.annotation)
    
    // Types
    applyPatternHighlighting(builder, text, "\\b[A-Z]\\w*\\b", colors.type)
}

/**
 * Highlighting for Python
 */
private fun applyPythonHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Keywords
    val keywords = listOf(
        "def", "class", "if", "elif", "else", "for", "while", "try", "except", "finally",
        "import", "from", "as", "return", "yield", "lambda", "with", "assert", "global",
        "nonlocal", "pass", "break", "continue", "and", "or", "not", "in", "is"
    )
    
    applyPatternHighlighting(builder, text, keywords.joinToString("|") { "\\b$it\\b" }, colors.keyword)
    
    // Strings
    applyPatternHighlighting(builder, text, "\"\"\".*?\"\"\"", colors.string)
    applyPatternHighlighting(builder, text, "'''.*?'''", colors.string)
    applyPatternHighlighting(builder, text, "\"([^\"\\\\]|\\\\.)*\"", colors.string)
    applyPatternHighlighting(builder, text, "'([^'\\\\]|\\\\.)*'", colors.string)
    
    // Numbers
    applyPatternHighlighting(builder, text, "\\b\\d+(\\.\\d+)?\\b", colors.number)
    
    // Comments
    applyPatternHighlighting(builder, text, "#.*$", colors.comment)
    
    // Built-ins
    val builtins = listOf("print", "len", "range", "enumerate", "zip", "map", "filter", "sorted")
    applyPatternHighlighting(builder, text, builtins.joinToString("|") { "\\b$it\\b" }, colors.builtin)
}

/**
 * Highlighting for JavaScript/TypeScript
 */
private fun applyJavaScriptHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Keywords
    val keywords = listOf(
        "function", "const", "let", "var", "if", "else", "for", "while", "do", "switch",
        "case", "default", "return", "break", "continue", "try", "catch", "finally",
        "throw", "new", "this", "class", "extends", "import", "export", "from", "as",
        "interface", "type", "enum", "namespace", "async", "await"
    )
    
    applyPatternHighlighting(builder, text, keywords.joinToString("|") { "\\b$it\\b" }, colors.keyword)
    
    // Strings
    applyPatternHighlighting(builder, text, "`[^`]*`", colors.string) // Template literals
    applyPatternHighlighting(builder, text, "\"([^\"\\\\]|\\\\.)*\"", colors.string)
    applyPatternHighlighting(builder, text, "'([^'\\\\]|\\\\.)*'", colors.string)
    
    // Numbers
    applyPatternHighlighting(builder, text, "\\b\\d+(\\.\\d+)?\\b", colors.number)
    
    // Comments
    applyPatternHighlighting(builder, text, "//.*$", colors.comment)
    applyPatternHighlighting(builder, text, "/\\*.*?\\*/", colors.comment)
    
    // Built-ins
    val builtins = listOf("console", "window", "document", "Array", "Object", "String", "Number")
    applyPatternHighlighting(builder, text, builtins.joinToString("|") { "\\b$it\\b" }, colors.builtin)
}

/**
 * Highlighting for C-style languages
 */
private fun applyCStyleHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Keywords
    val keywords = listOf(
        "int", "float", "double", "char", "void", "long", "short", "unsigned", "signed",
        "if", "else", "for", "while", "do", "switch", "case", "default", "return",
        "break", "continue", "struct", "union", "enum", "typedef", "sizeof",
        "fn", "let", "mut", "match", "impl", "use", "pub", "mod", "crate"
    )
    
    applyPatternHighlighting(builder, text, keywords.joinToString("|") { "\\b$it\\b" }, colors.keyword)
    
    // Preprocessor directives
    applyPatternHighlighting(builder, text, "#\\w+", colors.preprocessor)
    
    // Strings
    applyPatternHighlighting(builder, text, "\"([^\"\\\\]|\\\\.)*\"", colors.string)
    applyPatternHighlighting(builder, text, "'([^'\\\\]|\\\\.)*'", colors.string)
    
    // Numbers
    applyPatternHighlighting(builder, text, "\\b\\d+(\\.\\d+)?[fLdD]?\\b", colors.number)
    
    // Comments
    applyPatternHighlighting(builder, text, "//.*$", colors.comment)
    applyPatternHighlighting(builder, text, "/\\*.*?\\*/", colors.comment)
}

/**
 * Highlighting for markup languages (HTML, XML)
 */
private fun applyMarkupHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Tags
    applyPatternHighlighting(builder, text, "</?\\w+[^>]*>", colors.tag)
    
    // Attributes
    applyPatternHighlighting(builder, text, "\\w+(?=\\s*=)", colors.attribute)
    
    // Attribute values
    applyPatternHighlighting(builder, text, "=\"[^\"]*\"", colors.string)
    applyPatternHighlighting(builder, text, "='[^']*'", colors.string)
    
    // Comments
    applyPatternHighlighting(builder, text, "<!--.*?-->", colors.comment)
}

/**
 * Highlighting for CSS
 */
private fun applyCSSHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Selectors
    applyPatternHighlighting(builder, text, "\\.[\\w-]+", colors.cssClass)
    applyPatternHighlighting(builder, text, "#[\\w-]+", colors.cssId)
    applyPatternHighlighting(builder, text, "\\b\\w+(?=\\s*\\{)", colors.tag)
    
    // Properties
    applyPatternHighlighting(builder, text, "\\b[\\w-]+(?=\\s*:)", colors.attribute)
    
    // Values
    applyPatternHighlighting(builder, text, ":\\s*[^;\\}]+", colors.string)
    
    // Colors
    applyPatternHighlighting(builder, text, "#[0-9a-fA-F]{3,6}\\b", colors.number)
    
    // Comments
    applyPatternHighlighting(builder, text, "/\\*.*?\\*/", colors.comment)
}

/**
 * Highlighting for JSON
 */
private fun applyJSONHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Keys
    applyPatternHighlighting(builder, text, "\"[^\"]*\"(?=\\s*:)", colors.jsonKey)
    
    // String values
    applyPatternHighlighting(builder, text, ":\\s*\"[^\"]*\"", colors.string)
    
    // Numbers
    applyPatternHighlighting(builder, text, ":\\s*-?\\d+(\\.\\d+)?", colors.number)
    
    // Booleans and null
    applyPatternHighlighting(builder, text, "\\b(true|false|null)\\b", colors.keyword)
}

/**
 * Highlighting for SQL
 */
private fun applySQLHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Keywords
    val keywords = listOf(
        "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP",
        "ALTER", "INDEX", "TABLE", "DATABASE", "JOIN", "LEFT", "RIGHT", "INNER",
        "ON", "AS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET"
    )
    
    applyPatternHighlighting(builder, text, keywords.joinToString("|") { "\\b$it\\b" }, colors.keyword)
    
    // Strings
    applyPatternHighlighting(builder, text, "'([^'\\\\]|\\\\.)*'", colors.string)
    
    // Numbers
    applyPatternHighlighting(builder, text, "\\b\\d+(\\.\\d+)?\\b", colors.number)
    
    // Comments
    applyPatternHighlighting(builder, text, "--.*$", colors.comment)
}

/**
 * Highlighting for Bash
 */
private fun applyBashHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Keywords
    val keywords = listOf("if", "then", "else", "elif", "fi", "for", "while", "do", "done", "function")
    applyPatternHighlighting(builder, text, keywords.joinToString("|") { "\\b$it\\b" }, colors.keyword)
    
    // Variables
    applyPatternHighlighting(builder, text, "\\$\\{?\\w+\\}?", colors.variable)
    
    // Strings
    applyPatternHighlighting(builder, text, "\"([^\"\\\\]|\\\\.)*\"", colors.string)
    applyPatternHighlighting(builder, text, "'([^'\\\\]|\\\\.)*'", colors.string)
    
    // Comments
    applyPatternHighlighting(builder, text, "#.*$", colors.comment)
}

/**
 * Generic highlighting for unknown languages
 */
private fun applyGenericHighlighting(builder: AnnotatedString.Builder, text: String) {
    val colors = SyntaxColors()
    
    // Strings
    applyPatternHighlighting(builder, text, "\"([^\"\\\\]|\\\\.)*\"", colors.string)
    applyPatternHighlighting(builder, text, "'([^'\\\\]|\\\\.)*'", colors.string)
    
    // Numbers
    applyPatternHighlighting(builder, text, "\\b\\d+(\\.\\d+)?\\b", colors.number)
    
    // Comments (common patterns)
    applyPatternHighlighting(builder, text, "//.*$", colors.comment)
    applyPatternHighlighting(builder, text, "#.*$", colors.comment)
    applyPatternHighlighting(builder, text, "/\\*.*?\\*/", colors.comment)
}

/**
 * Apply pattern-based highlighting to text
 */
private fun applyPatternHighlighting(
    builder: AnnotatedString.Builder,
    text: String,
    pattern: String,
    color: Color
) {
    try {
        val regex = Pattern.compile(pattern, Pattern.MULTILINE or Pattern.DOTALL)
        val matcher = regex.matcher(text)
        
        while (matcher.find()) {
            builder.addStyle(
                style = SpanStyle(color = color),
                start = matcher.start(),
                end = matcher.end()
            )
        }
    } catch (e: Exception) {
        // Ignore regex errors
    }
}

/**
 * Color scheme for syntax highlighting
 */
@Composable
private fun SyntaxColors() = SyntaxColorScheme(
    keyword = Color(0xFF569CD6),        // Blue
    string = Color(0xFF4FC1FF),         // Light blue
    comment = Color(0xFF6A9955),        // Green
    number = Color(0xFFB5CEA8),         // Light green
    type = Color(0xFF4EC9B0),           // Teal
    builtin = Color(0xFFDCDCAA),        // Yellow
    annotation = Color(0xFFFFD700),     // Gold
    preprocessor = Color(0xFFC586C0),   // Pink
    tag = Color(0xFF569CD6),            // Blue
    attribute = Color(0xFF92C5F8),      // Light blue
    cssClass = Color(0xFFD7BA7D),       // Orange
    cssId = Color(0xFFFFC66D),          // Light orange  
    jsonKey = Color(0xFF4FC1FF),        // Light blue
    variable = Color(0xFF9CDCFE)        // Very light blue
)

/**
 * Data class for syntax color scheme
 */
private data class SyntaxColorScheme(
    val keyword: Color,
    val string: Color,
    val comment: Color,
    val number: Color,
    val type: Color,
    val builtin: Color,
    val annotation: Color,
    val preprocessor: Color,
    val tag: Color,
    val attribute: Color,
    val cssClass: Color,
    val cssId: Color,
    val jsonKey: Color,
    val variable: Color
)