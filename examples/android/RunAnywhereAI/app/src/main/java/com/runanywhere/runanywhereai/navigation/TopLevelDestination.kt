package com.runanywhere.runanywhereai.navigation

import androidx.compose.ui.graphics.vector.ImageVector
import com.runanywhere.runanywhereai.ui.icons.RAIcons

// Bottom navigation tab definitions
enum class TopLevelDestination(
    val route: Route,
    val icon: ImageVector,
    val selectedIcon: ImageVector,
    val label: String,
) {
    CHAT(Route.Chat, RAIcons.Chat, RAIcons.ChatFilled, "Chat"),
    VISION(Route.Vision, RAIcons.Eye, RAIcons.EyeFilled, "Vision"),
    VOICE(Route.Voice, RAIcons.Mic, RAIcons.MicFilled, "Voice"),
    MORE(Route.More, RAIcons.LayoutGrid, RAIcons.LayoutGridFilled, "More"),
    SETTINGS(Route.Settings, RAIcons.Settings, RAIcons.SettingsFilled, "Settings"),
}
