package com.runanywhere.runanywhereai.ui.navigation

import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import kotlinx.serialization.Serializable

// Type-safe routes. Add args as constructor params, e.g. @Serializable data class ChatThread(val id: String)
@Serializable
data object Chat

@Serializable
data object Voice

@Serializable
data object More

@Serializable
data object Settings

@Serializable
data object Tools

@Serializable
data object Tts

@Serializable
data object Stt

@Serializable
data object Vad

@Serializable
data object Vision

@Serializable
data object Documents

@Serializable
data object Solutions

@Serializable
data object CloudProviders

@Serializable
data object Benchmarks

@Serializable
data class BenchmarkDetail(val runId: String)

// Destinations shown in the bottom bar. selectedIcon defaults to icon when there's no filled variant.
enum class TopLevelDestination(
    val route: Any,
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector = icon,
) {
    CHAT(Chat, "Chat", RACIcons.Outline.MessageCircle, RACIcons.Filled.MessageCircle),
    VOICE(Voice, "Voice", RACIcons.Outline.Microphone),
    MORE(More, "More", RACIcons.Outline.Menu),
}

// Shared by the bottom bar and the nav rail so their nav behaviour stays identical.
fun NavDestination?.isSelected(route: Any): Boolean =
    this?.hierarchy?.any { it.hasRoute(route::class) } == true

fun NavHostController.navigateTopLevel(route: Any) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}
