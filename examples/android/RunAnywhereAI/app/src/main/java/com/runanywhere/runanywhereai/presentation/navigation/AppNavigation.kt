package com.runanywhere.runanywhereai.presentation.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.runanywhere.runanywhereai.presentation.benchmarks.views.BenchmarkDashboardScreen
import com.runanywhere.runanywhereai.presentation.benchmarks.views.BenchmarkDetailScreen
import com.runanywhere.runanywhereai.presentation.chat.ChatScreen
import com.runanywhere.runanywhereai.presentation.components.AppBottomNavigationBar
import com.runanywhere.runanywhereai.presentation.components.BottomNavTab
import com.runanywhere.runanywhereai.presentation.rag.DocumentRAGScreen
import com.runanywhere.runanywhereai.presentation.settings.SettingsScreen
import com.runanywhere.runanywhereai.presentation.stt.SpeechToTextScreen
import com.runanywhere.runanywhereai.presentation.tts.TextToSpeechScreen
import com.runanywhere.runanywhereai.presentation.vision.VLMScreen
import com.runanywhere.runanywhereai.presentation.vision.VisionHubScreen
import com.runanywhere.runanywhereai.presentation.voice.VoiceAssistantScreen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppNavigation() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val selectedTab = routeToBottomNavTab(currentDestination?.route)

    Scaffold(
        bottomBar = {
            AppBottomNavigationBar(
                selectedTab = selectedTab,
                onTabSelected = { tab ->
                    val route = bottomNavTabToRoute(tab)
                    navController.navigate(route) {
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                },
            )
        },
    ) { paddingValues ->
        NavHost(
            navController = navController,
            startDestination = NavigationRoute.CHAT,
            modifier = Modifier.padding(paddingValues),
        ) {
            composable(NavigationRoute.CHAT) {
                ChatScreen()
            }

            composable(NavigationRoute.VISION) {
                VisionHubScreen(
                    onNavigateToVLM = {
                        navController.navigate(NavigationRoute.VLM)
                    },
                    onNavigateToImageGeneration = {
                        // Future
                    },
                )
            }

            composable(NavigationRoute.VLM) {
                VLMScreen()
            }

            composable(NavigationRoute.VOICE) {
                VoiceAssistantScreen()
            }

            // "More" hub routes — STT, TTS, RAG, and Benchmarks here to match iOS structure
            composable(NavigationRoute.MORE) {
                MoreHubScreen(
                    onNavigateToSTT = {
                        navController.navigate(NavigationRoute.STT)
                    },
                    onNavigateToTTS = {
                        navController.navigate(NavigationRoute.TTS)
                    },
                    onNavigateToRAG = {
                        navController.navigate(NavigationRoute.RAG)
                    },
                    onNavigateToBenchmarks = {
                        navController.navigate(NavigationRoute.BENCHMARKS)
                    },
                )
            }

            composable(NavigationRoute.STT) {
                SpeechToTextScreen()
            }

            composable(NavigationRoute.TTS) {
                TextToSpeechScreen()
            }

            composable(NavigationRoute.RAG) {
                DocumentRAGScreen()
            }

            composable(NavigationRoute.BENCHMARKS) {
                BenchmarkDashboardScreen(
                    onNavigateToDetail = { runId ->
                        navController.navigate("${NavigationRoute.BENCHMARK_DETAIL}/$runId")
                    },
                )
            }

            composable("${NavigationRoute.BENCHMARK_DETAIL}/{runId}") { backStackEntry ->
                val runId = backStackEntry.arguments?.getString("runId") ?: return@composable
                BenchmarkDetailScreen(runId = runId)
            }

            composable(NavigationRoute.SETTINGS) {
                SettingsScreen()
            }
        }
    }
}

/**
 * Maps current route to bottom nav tab, including nested/child routes.
 */
private fun routeToBottomNavTab(route: String?): BottomNavTab {
    return when {
        route == null -> BottomNavTab.Chat
        route == NavigationRoute.CHAT -> BottomNavTab.Chat
        route == NavigationRoute.VISION || route == NavigationRoute.VLM -> BottomNavTab.Vision
        route == NavigationRoute.VOICE -> BottomNavTab.Voice
        route in listOf(
            NavigationRoute.MORE,
            NavigationRoute.STT,
            NavigationRoute.TTS,
            NavigationRoute.RAG,
            NavigationRoute.BENCHMARKS,
        ) || route.startsWith(NavigationRoute.BENCHMARK_DETAIL) -> BottomNavTab.More
        route == NavigationRoute.SETTINGS -> BottomNavTab.Settings
        else -> BottomNavTab.Chat
    }
}

private fun bottomNavTabToRoute(tab: BottomNavTab): String {
    return when (tab) {
        BottomNavTab.Chat -> NavigationRoute.CHAT
        BottomNavTab.Vision -> NavigationRoute.VISION
        BottomNavTab.Voice -> NavigationRoute.VOICE
        BottomNavTab.More -> NavigationRoute.MORE
        BottomNavTab.Settings -> NavigationRoute.SETTINGS
    }
}

object NavigationRoute {
    const val CHAT = "chat"
    const val VISION = "vision"
    const val VLM = "vlm"
    const val VOICE = "voice"
    const val MORE = "more"
    const val STT = "stt"
    const val TTS = "tts"
    const val RAG = "rag"
    const val BENCHMARKS = "benchmarks"
    const val BENCHMARK_DETAIL = "benchmark_detail"
    const val SETTINGS = "settings"
}