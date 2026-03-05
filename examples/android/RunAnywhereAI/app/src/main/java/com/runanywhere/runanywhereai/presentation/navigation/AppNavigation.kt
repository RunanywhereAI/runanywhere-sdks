package com.runanywhere.runanywhereai.presentation.navigation

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
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
import com.runanywhere.runanywhereai.presentation.components.LocalTopBarState
import com.runanywhere.runanywhereai.presentation.components.TopBarState
import com.runanywhere.runanywhereai.presentation.lora.LoraManagerScreen
import com.runanywhere.runanywhereai.presentation.rag.DocumentRAGScreen
import com.runanywhere.runanywhereai.presentation.settings.SettingsScreen
import com.runanywhere.runanywhereai.presentation.stt.SpeechToTextScreen
import com.runanywhere.runanywhereai.presentation.tts.TextToSpeechScreen
import com.runanywhere.runanywhereai.presentation.vision.VLMScreen
import com.runanywhere.runanywhereai.presentation.vision.VisionHubScreen
import com.runanywhere.runanywhereai.presentation.voice.VoiceAssistantScreen

private const val TRANSITION_DURATION = 300
private const val SLIDE_OFFSET_FRACTION = 4 // 1/4 of width

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppNavigation() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val selectedTab = routeToBottomNavTab(currentDestination?.route)
    val topBarState = remember { TopBarState() }

    val density = LocalDensity.current
    val isKeyboardOpen = WindowInsets.ime.getBottom(density) > 0

    CompositionLocalProvider(LocalTopBarState provides topBarState) {
        Scaffold(
            topBar = {
                val custom = topBarState.customTopBar
                if (custom != null) {
                    custom()
                } else {
                    TopAppBar(
                        title = { Text(topBarState.title) },
                        navigationIcon = {
                            if (topBarState.showBack) {
                                IconButton(onClick = { topBarState.onBack?.invoke() }) {
                                    Icon(
                                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                        contentDescription = "Back",
                                    )
                                }
                            }
                        },
                        actions = topBarState.actions,
                        colors = TopAppBarDefaults.topAppBarColors(
                            containerColor = MaterialTheme.colorScheme.surface,
                        ),
                    )
                }
            },
            bottomBar = {
                if (!isKeyboardOpen) {
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
                }
            },
        ) { paddingValues ->
            NavHost(
                navController = navController,
                startDestination = NavigationRoute.CHAT,
                modifier = Modifier
                    .padding(paddingValues)
                    .then(if (isKeyboardOpen) Modifier.imePadding() else Modifier),
                enterTransition = {
                    slideInHorizontally(
                        initialOffsetX = { it / SLIDE_OFFSET_FRACTION },
                        animationSpec = tween(TRANSITION_DURATION, easing = FastOutSlowInEasing),
                    ) + fadeIn(animationSpec = tween(TRANSITION_DURATION))
                },
                exitTransition = {
                    slideOutHorizontally(
                        targetOffsetX = { -it / SLIDE_OFFSET_FRACTION },
                        animationSpec = tween(TRANSITION_DURATION, easing = FastOutSlowInEasing),
                    ) + fadeOut(animationSpec = tween(TRANSITION_DURATION))
                },
                popEnterTransition = {
                    slideInHorizontally(
                        initialOffsetX = { -it / SLIDE_OFFSET_FRACTION },
                        animationSpec = tween(TRANSITION_DURATION, easing = FastOutSlowInEasing),
                    ) + fadeIn(animationSpec = tween(TRANSITION_DURATION))
                },
                popExitTransition = {
                    slideOutHorizontally(
                        targetOffsetX = { it / SLIDE_OFFSET_FRACTION },
                        animationSpec = tween(TRANSITION_DURATION, easing = FastOutSlowInEasing),
                    ) + fadeOut(animationSpec = tween(TRANSITION_DURATION))
                },
            ) {
                composable(NavigationRoute.CHAT) {
                    ChatScreen()
                }

                composable(NavigationRoute.VISION) {
                    VisionHubScreen(
                        onNavigateToVLM = {
                            navController.navigate(NavigationRoute.VLM)
                        },
                    )
                }

                composable(NavigationRoute.VLM) {
                    VLMScreen(
                        onBack = { navController.popBackStack() },
                    )
                }

                composable(NavigationRoute.VOICE) {
                    VoiceAssistantScreen()
                }

                // "More" hub routes
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
                        onNavigateToLoraManager = {
                            navController.navigate(NavigationRoute.LORA_MANAGER)
                        },
                    )
                }

                composable(NavigationRoute.STT) {
                    SpeechToTextScreen(
                        onBack = { navController.popBackStack() },
                    )
                }

                composable(NavigationRoute.TTS) {
                    TextToSpeechScreen(
                        onBack = { navController.popBackStack() },
                    )
                }

                composable(NavigationRoute.RAG) {
                    DocumentRAGScreen(
                        onBack = { navController.popBackStack() },
                    )
                }

                composable(NavigationRoute.BENCHMARKS) {
                    BenchmarkDashboardScreen(
                        onNavigateToDetail = { runId ->
                            navController.navigate("${NavigationRoute.BENCHMARK_DETAIL}/$runId")
                        },
                        onBack = { navController.popBackStack() },
                    )
                }

                composable("${NavigationRoute.BENCHMARK_DETAIL}/{runId}") { backStackEntry ->
                    val runId = backStackEntry.arguments?.getString("runId") ?: return@composable
                    BenchmarkDetailScreen(
                        runId = runId,
                        onBack = { navController.popBackStack() },
                    )
                }

                composable(NavigationRoute.LORA_MANAGER) {
                    LoraManagerScreen(
                        onBack = { navController.popBackStack() },
                    )
                }

                composable(NavigationRoute.SETTINGS) {
                    SettingsScreen()
                }
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
            NavigationRoute.LORA_MANAGER,
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
    const val LORA_MANAGER = "lora_manager"
    const val SETTINGS = "settings"
}
