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
data class Vision(val openLiveCamera: Boolean = false)

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

enum class ConsumerNavGroup(val title: String) {
    ASSISTANT("Assistant"),
    LIBRARY("Library"),
    ADVANCED("Advanced"),
}

enum class ConsumerDestination(
    val route: Any,
    val label: String,
    val description: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector = icon,
    val group: ConsumerNavGroup,
) {
    CHAT(
        Chat,
        "Ask",
        "Private chat assistant",
        RACIcons.Outline.MessageCircle,
        RACIcons.Filled.MessageCircle,
        ConsumerNavGroup.ASSISTANT,
    ),
    TALK(
        Voice,
        "Talk",
        "Hands-free voice assistant",
        RACIcons.Outline.Microphone,
        RACIcons.Filled.Microphone,
        ConsumerNavGroup.ASSISTANT,
    ),
    LIVE(
        Vision(),
        "Images & live",
        "Ask about photos or camera",
        RACIcons.Outline.Eye,
        group = ConsumerNavGroup.ASSISTANT,
    ),
    DOCUMENTS(
        Documents,
        "Documents",
        "Ask questions with sources",
        RACIcons.Outline.FileText,
        group = ConsumerNavGroup.ASSISTANT,
    ),
    SETTINGS(
        Settings,
        "Settings",
        "Personalization and downloads",
        RACIcons.Outline.Settings,
        RACIcons.Filled.Settings,
        ConsumerNavGroup.LIBRARY,
    ),
    ADVANCED(
        More,
        "Advanced",
        "SDK tools and diagnostics",
        RACIcons.Outline.Stack,
        group = ConsumerNavGroup.ADVANCED,
    ),
}

// Shared by drawer and programmatic top-level jumps so back stack behavior stays identical.
fun NavDestination?.isSelected(route: Any): Boolean =
    this?.hierarchy?.any { it.hasRoute(route::class) } == true

fun NavDestination?.isConsumerTopLevel(): Boolean =
    ConsumerDestination.entries.any { isSelected(it.route) }

fun NavHostController.navigateTopLevel(route: Any, restoreState: Boolean = true) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        this.restoreState = restoreState
    }
}
