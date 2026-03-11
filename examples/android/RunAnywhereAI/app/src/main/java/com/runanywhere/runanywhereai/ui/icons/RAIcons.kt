package com.runanywhere.runanywhereai.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

// RunAnywhere Icons — built from Tabler & Lucide SVG path data.
// Usage: Icon(RAIcons.Chat, contentDescription = "Chat")
object RAIcons {

    // Navigation — outlined
    val Chat by lazy { strokeIcon("Chat", "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z") }
    val Mic by lazy { strokeIcon("Mic", "M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z", "M19 10v2a7 7 0 0 1-14 0v-2", "M12 19v3") }
    val Eye by lazy { strokeIcon("Eye", "M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z", "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z") }
    val Settings by lazy {
        strokeIcon(
            "Settings",
            "M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z",
            "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z"
        )
    }
    val LayoutGrid by lazy { strokeIcon("LayoutGrid", "M3 3h7v7H3z", "M14 3h7v7h-7z", "M14 14h7v7h-7z", "M3 14h7v7H3z") }

    // Navigation — filled (selected state)
    val ChatFilled by lazy { filledStrokeIcon("ChatFilled", "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z") }
    val MicFilled by lazy { filledStrokeIcon("MicFilled", "M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z", "M19 10v2a7 7 0 0 1-14 0v-2", "M12 19v3") }
    val EyeFilled by lazy { filledStrokeIcon("EyeFilled", "M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z", "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z") }
    val SettingsFilled by lazy {
        filledStrokeIcon(
            "SettingsFilled",
            "M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z",
            "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z"
        )
    }
    val LayoutGridFilled by lazy { filledStrokeIcon("LayoutGridFilled", "M3 3h7v7H3z", "M14 3h7v7h-7z", "M14 14h7v7h-7z", "M3 14h7v7H3z") }

    // Actions
    val Send by lazy {
        strokeIcon(
            "Send",
            "M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z",
            "M21.854 2.147l-10.94 10.939"
        )
    }
    val Plus by lazy { strokeIcon("Plus", "M5 12h14", "M12 5v14") }
    val X by lazy { strokeIcon("X", "M18 6 6 18", "M6 6l12 12") }
    val ChevronLeft by lazy { strokeIcon("ChevronLeft", "m15 18-6-6 6-6") }
    val ChevronRight by lazy { strokeIcon("ChevronRight", "m9 18 6-6-6-6") }
    val Copy by lazy {
        strokeIcon(
            "Copy",
            "M9 2H5a2 2 0 0 0-2 2v4",
            "M9 2h6a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2Z",
            "M13 14v4a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2Z"
        )
    }
    val Trash by lazy { strokeIcon("Trash", "M3 6h18", "M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6", "M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2") }

    // Status
    val Check by lazy { strokeIcon("Check", "M20 6 9 17l-5-5") }
    val AlertCircle by lazy { strokeIcon("AlertCircle", "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Z", "M12 8v4", "M12 16h.01") }
    val Loader by lazy { strokeIcon("Loader", "M12 2v4", "M12 18v4", "M4.93 4.93l2.83 2.83", "M16.24 16.24l2.83 2.83", "M2 12h4", "M18 12h4", "M4.93 19.07l2.83-2.83", "M16.24 7.76l2.83-2.83") }
    val Download by lazy { strokeIcon("Download", "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4", "M7 10l5 5 5-5", "M12 15V3") }

    // Media
    val Play by lazy { strokeIcon("Play", "m6 3 14 9-14 9V3z") }
    val Stop by lazy { strokeIcon("Stop", "M6 4h4v16H6z", "M14 4h4v16h-4z") }
    val Camera by lazy { strokeIcon("Camera", "M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3z", "M12 11a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z") }

    // Features
    val FileText by lazy { strokeIcon("FileText", "M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7z", "M14 2v4a2 2 0 0 0 2 2h4", "M10 9H8", "M16 13H8", "M16 17H8") }
    val Sparkles by lazy {
        strokeIcon(
            "Sparkles",
            "M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z",
            "M20 3v4",
            "M22 5h-4"
        )
    }
    val Gauge by lazy { strokeIcon("Gauge", "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Z", "M12 16a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z", "M13.41 12.59l4.24-4.24") }
    val Puzzle by lazy {
        strokeIcon(
            "Puzzle",
            "M15.39 4.39a1 1 0 0 0 .61.22 2.5 2.5 0 0 1 0 5 1 1 0 0 0-1 1V15a2 2 0 0 1-2 2h-4.39a1 1 0 0 1-.61-.22 2.5 2.5 0 0 0-4 2 1 1 0 0 1-1 .78H3a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v.39z"
        )
    }

    // Utility
    val History by lazy { strokeIcon("History", "M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8", "M3 3v5h5", "M12 7v5l4 2") }
    val ChevronDown by lazy { strokeIcon("ChevronDown", "m6 9 6 6 6-6") }
    val CloudDownload by lazy { strokeIcon("CloudDownload", "M12 13v8l-4-4", "M12 21l4-4", "M4.393 15.269A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.436 8.284") }
    val CircleCheck by lazy { strokeIcon("CircleCheck", "M22 11.08V12a10 10 0 1 1-5.93-9.14", "m9 11 3 3L22 4") }

    // Audio
    val Volume2 by lazy { strokeIcon("Volume2", "M11 5 6 9H2v6h4l5 4V5Z", "M15.54 8.46a5 5 0 0 1 0 7.07", "M19.07 4.93a10 10 0 0 1 0 14.14") }
    val Activity by lazy { strokeIcon("Activity", "M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2") }
    val Zap by lazy { strokeIcon("Zap", "M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z") }
    val Clock by lazy { strokeIcon("Clock", "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Z", "M12 6v6l4 2") }

    // Hardware
    val Smartphone by lazy { strokeIcon("Smartphone", "M11 4h2", "M12 17h.01", "M7 2h10a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z") }
    val Cpu by lazy { strokeIcon("Cpu", "M6 6h12v12H6z", "M9 9h6v6H9z", "M2 12h4", "M18 12h4", "M12 2v4", "M12 18v4") }
    val HardDrive by lazy { strokeIcon("HardDrive", "M22 12H2", "M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z", "M6 16h.01", "M10 16h.01") }
}

// Builds a 24x24 stroke-based icon from SVG path data strings.
private fun strokeIcon(name: String, vararg paths: String): ImageVector =
    ImageVector.Builder(
        name = "RAIcons.$name",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        val nodes = paths.map { PathParser().parsePathString(it).toNodes() }
        nodes.forEach { pathNodes ->
            addPath(
                pathData = pathNodes,
                fill = null,
                stroke = SolidColor(Color.Black),
                strokeLineWidth = 2f,
                strokeLineCap = StrokeCap.Round,
                strokeLineJoin = StrokeJoin.Round,
            )
        }
    }.build()

// Builds a 24x24 filled + stroked icon (for selected/active states).
private fun filledStrokeIcon(name: String, vararg paths: String): ImageVector =
    ImageVector.Builder(
        name = "RAIcons.$name",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        val nodes = paths.map { PathParser().parsePathString(it).toNodes() }
        nodes.forEach { pathNodes ->
            addPath(
                pathData = pathNodes,
                fill = SolidColor(Color.Black),
                stroke = SolidColor(Color.Black),
                strokeLineWidth = 2f,
                strokeLineCap = StrokeCap.Round,
                strokeLineJoin = StrokeJoin.Round,
            )
        }
    }.build()

// Builds a 24x24 fill-based icon from SVG path data strings.
@Suppress("unused")
private fun fillIcon(name: String, vararg paths: String): ImageVector =
    ImageVector.Builder(
        name = "RAIcons.$name",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
    ).apply {
        val nodes = paths.map { PathParser().parsePathString(it).toNodes() }
        nodes.forEach { pathNodes ->
            addPath(
                pathData = pathNodes,
                fill = SolidColor(Color.Black),
            )
        }
    }.build()
