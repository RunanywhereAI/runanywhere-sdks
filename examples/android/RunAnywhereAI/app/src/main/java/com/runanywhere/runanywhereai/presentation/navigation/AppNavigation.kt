package com.runanywhere.runanywhereai.presentation.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.runanywhere.runanywhereai.presentation.chat.ChatScreen
import com.runanywhere.runanywhereai.presentation.settings.SettingsScreen
import com.runanywhere.runanywhereai.presentation.stt.SpeechToTextScreen
import com.runanywhere.runanywhereai.presentation.tts.TextToSpeechScreen
import com.runanywhere.runanywhereai.presentation.vision.VLMScreen
import com.runanywhere.runanywhereai.presentation.vision.VisionHubScreen
import com.runanywhere.runanywhereai.presentation.voice.VoiceAssistantScreen
import com.runanywhere.runanywhereai.ui.theme.AppColors

/**
 * Main navigation component matching iOS app structure exactly.
 * 5 tabs: Chat, Vision, Voice, More, Settings
 *
 * iOS Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/App/ContentView.swift
 */
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

            // Vision hub — matches iOS VisionHubView
            composable(NavigationRoute.VISION) {
                VisionHubScreen(
                    onNavigateToVLM = {
                        navController.navigate(NavigationRoute.VLM)
                    },
                    onNavigateToImageGeneration = {
                        // Future: navigate to image generation screen
                    },
                )
            }

            // VLM screen — nested route from Vision hub
            composable(NavigationRoute.VLM) {
                VLMScreen()
            }

            composable(NavigationRoute.VOICE) {
                VoiceAssistantScreen()
            }

            // "More" hub routes — STT and TTS moved here to match iOS structure
            composable(NavigationRoute.MORE) {
                MoreHubScreen(
                    onNavigateToSTT = {
                        navController.navigate(NavigationRoute.STT)
                    },
                    onNavigateToTTS = {
                        navController.navigate(NavigationRoute.TTS)
                    },
                )
            }

            composable(NavigationRoute.STT) {
                SpeechToTextScreen()
            }

            composable(NavigationRoute.TTS) {
                TextToSpeechScreen()
            }

            composable(NavigationRoute.SETTINGS) {
                SettingsScreen()
            }
        }
    }
}

/**
 * Bottom navigation bar matching iOS tab bar design.
 *
 * iOS Reference: ContentView.swift - TabView with 5 tabs
 * - Chat (message icon)
 * - Vision (eye icon)
 * - Voice (mic icon)
 * - More (ellipsis icon)
 * - Settings (gear icon)
 */
@Composable
fun RunAnywhereBottomNav(navController: NavController) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    // Match iOS tab order exactly: Chat, Vision, Voice, More, Settings
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
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        modifier =
            Modifier
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .clip(RoundedCornerShape(24.dp)),
    ) {
        items.forEach { item ->
            val selected = currentDestination?.hierarchy?.any { it.route == item.route } == true

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
                        indicatorColor = AppColors.primaryAccent.copy(alpha = 0.1f),
                        unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                onClick = {
                    navController.navigate(item.route) {
                        // Pop up to the start destination to avoid building up a large stack
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        // Avoid multiple copies of the same destination
                        launchSingleTop = true
                        // Restore state when reselecting a previously selected item
                        restoreState = true
                    }
                },
            )
        }
    }
}

/**
 * Navigation routes matching iOS tabs exactly.
 *
 * iOS Reference: ContentView.swift TabView
 */
object NavigationRoute {
    const val CHAT = "chat"
    const val VISION = "vision"
    const val VLM = "vlm"
    const val VOICE = "voice"
    const val MORE = "more"
    const val STT = "stt"
    const val TTS = "tts"
    const val SETTINGS = "settings"
}

/**
 * Bottom navigation item data
 */
data class BottomNavItem(
    val route: String,
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector = icon,
)
