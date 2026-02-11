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
import com.runanywhere.runanywhereai.presentation.chat.ChatScreen
import com.runanywhere.runanywhereai.presentation.components.AppBottomNavigationBar
import com.runanywhere.runanywhereai.presentation.components.BottomNavTab
import com.runanywhere.runanywhereai.presentation.settings.SettingsScreen
import com.runanywhere.runanywhereai.presentation.stt.SpeechToTextScreen
import com.runanywhere.runanywhereai.presentation.tts.TextToSpeechScreen
import com.runanywhere.runanywhereai.presentation.voice.VoiceAssistantScreen

/**
 * Main navigation component
 * 5 tabs: Chat, Transcribe, Speak, Voice, Settings
 */
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

            composable(NavigationRoute.STT) {
                SpeechToTextScreen()
            }

            composable(NavigationRoute.TTS) {
                TextToSpeechScreen()
            }

            composable(NavigationRoute.VOICE) {
                VoiceAssistantScreen()
            }

            composable(NavigationRoute.SETTINGS) {
                SettingsScreen()
            }
        }
    }
}

private fun routeToBottomNavTab(route: String?): BottomNavTab {
    return when (route) {
        NavigationRoute.CHAT -> BottomNavTab.Chat
        NavigationRoute.STT -> BottomNavTab.Transcribe
        NavigationRoute.TTS -> BottomNavTab.Speak
        NavigationRoute.VOICE -> BottomNavTab.Voice
        NavigationRoute.SETTINGS -> BottomNavTab.Settings
        else -> BottomNavTab.Chat
    }
}

private fun bottomNavTabToRoute(tab: BottomNavTab): String {
    return when (tab) {
        BottomNavTab.Chat -> NavigationRoute.CHAT
        BottomNavTab.Transcribe -> NavigationRoute.STT
        BottomNavTab.Speak -> NavigationRoute.TTS
        BottomNavTab.Voice -> NavigationRoute.VOICE
        BottomNavTab.Settings -> NavigationRoute.SETTINGS
    }
}

/**
 * Navigation routes
 */
object NavigationRoute {
    const val CHAT = "chat"
    const val STT = "stt"
    const val TTS = "tts"
    const val VOICE = "voice"
    const val SETTINGS = "settings"
}
