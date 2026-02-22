package com.runanywhere.runanywhereai.presentation.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.runanywhere.runanywhereai.presentation.chat.ChatScreen
import com.runanywhere.runanywhereai.presentation.rag.DocumentRAGScreen
import com.runanywhere.runanywhereai.presentation.settings.SettingsScreen
import com.runanywhere.runanywhereai.presentation.stt.SpeechToTextScreen
import com.runanywhere.runanywhereai.presentation.tts.TextToSpeechScreen
import com.runanywhere.runanywhereai.presentation.vision.VLMScreen
import com.runanywhere.runanywhereai.presentation.vision.VisionHubScreen
import com.runanywhere.runanywhereai.presentation.voice.VoiceAssistantScreen
import com.runanywhere.runanywhereai.ui.theme.AppColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppNavigation() {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            RunAnywhereBottomNav(navController = navController)
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

            // ✅ More hub now includes RAG
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

            composable(NavigationRoute.SETTINGS) {
                SettingsScreen()
            }
        }
    }
}

/**
 * Ensures nested routes highlight correct tab
 */
private fun isRouteSelectedForTab(currentRoute: String?, tabRoute: String): Boolean {
    if (currentRoute == null) return false
    if (currentRoute == tabRoute) return true

    return when (tabRoute) {
        NavigationRoute.VISION ->
            currentRoute in listOf(NavigationRoute.VLM)

        NavigationRoute.MORE ->
            currentRoute in listOf(
                NavigationRoute.STT,
                NavigationRoute.TTS,
                NavigationRoute.RAG, // ✅ RAG mapped under More
            )

        else -> false
    }
}

@Composable
fun RunAnywhereBottomNav(navController: NavController) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    val items =
        listOf(
            BottomNavItem(
                route = NavigationRoute.CHAT,
                label = "Chat",
                icon = Icons.Outlined.Chat,
                selectedIcon = Icons.Filled.Chat,
            ),
            BottomNavItem(
                route = NavigationRoute.VISION,
                label = "Vision",
                icon = Icons.Outlined.Visibility,
                selectedIcon = Icons.Filled.Visibility,
            ),
            BottomNavItem(
                route = NavigationRoute.VOICE,
                label = "Voice",
                icon = Icons.Outlined.Mic,
                selectedIcon = Icons.Filled.Mic,
            ),
            BottomNavItem(
                route = NavigationRoute.MORE,
                label = "More",
                icon = Icons.Outlined.MoreHoriz,
                selectedIcon = Icons.Filled.MoreHoriz,
            ),
            BottomNavItem(
                route = NavigationRoute.SETTINGS,
                label = "Settings",
                icon = Icons.Outlined.Settings,
                selectedIcon = Icons.Filled.Settings,
            ),
        )

    NavigationBar(
        containerColor = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
    ) {
        items.forEach { item ->
            val selected = isRouteSelectedForTab(currentRoute, item.route)

            NavigationBarItem(
                icon = {
                    Icon(
                        imageVector = if (selected) item.selectedIcon else item.icon,
                        contentDescription = item.label,
                    )
                },
                label = { Text(item.label) },
                selected = selected,
                colors =
                    NavigationBarItemDefaults.colors(
                        selectedIconColor = AppColors.primaryAccent,
                        selectedTextColor = AppColors.primaryAccent,
                        indicatorColor = AppColors.primaryAccent.copy(alpha = 0.12f),
                        unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                onClick = {
                    navController.navigate(item.route) {
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                },
            )
        }
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
    const val SETTINGS = "settings"
}

data class BottomNavItem(
    val route: String,
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector = icon,
)