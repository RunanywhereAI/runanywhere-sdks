package com.runanywhere.runanywhereai.navigation

import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavDestination.Companion.hasRoute


// Describes the top bar variant for each screen
sealed interface TopBarType {
    // Standard top bar with title + optional back button
    data class Standard(val title: String, val showBack: Boolean = false) : TopBarType
    // Chat screen uses a custom top bar (model chip + actions)
    data object Chat : TopBarType
}

// Resolves the top bar type from the current navigation entry
fun resolveTopBar(entry: NavBackStackEntry?): TopBarType {
    val dest = entry?.destination ?: return TopBarType.Standard("RunAnywhere")

    return when {
        dest.hasRoute<Route.Chat>() -> TopBarType.Chat
        dest.hasRoute<Route.Vision>() -> TopBarType.Standard("Vision")
        dest.hasRoute<Route.Voice>() -> TopBarType.Standard("Voice")
        dest.hasRoute<Route.More>() -> TopBarType.Standard("More")
        dest.hasRoute<Route.Settings>() -> TopBarType.Standard("Settings")
        dest.hasRoute<Route.Vlm>() -> TopBarType.Standard("Vision Chat", showBack = true)
        dest.hasRoute<Route.Stt>() -> TopBarType.Standard("Speech to Text", showBack = true)
        dest.hasRoute<Route.Tts>() -> TopBarType.Standard("Text to Speech", showBack = true)
        dest.hasRoute<Route.Rag>() -> TopBarType.Standard("Document Q&A", showBack = true)
        dest.hasRoute<Route.LoraManager>() -> TopBarType.Standard("LoRA Adapters", showBack = true)
        dest.hasRoute<Route.Benchmarks>() -> TopBarType.Standard("Benchmarks", showBack = true)
        dest.hasRoute<Route.BenchmarkDetail>() -> {
            TopBarType.Standard("Benchmark Details", showBack = true)
        }
        else -> TopBarType.Standard("RunAnywhere")
    }
}
