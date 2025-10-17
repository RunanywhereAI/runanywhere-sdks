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
import androidx.navigation.NavController
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.runanywhere.runanywhereai.presentation.chat.ChatScreen
import com.runanywhere.runanywhereai.presentation.storage.StorageScreen
import com.runanywhere.runanywhereai.presentation.settings.SettingsScreen
import com.runanywhere.runanywhereai.presentation.quiz.QuizScreen
import com.runanywhere.runanywhereai.presentation.voice.VoiceAssistantScreen

/**
 * Main navigation component matching iOS app structure
 * 5 tabs: Chat, Storage, Settings, Quiz, Voice
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppNavigation() {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            BottomNavigationBar(navController = navController)
        }
    ) { paddingValues ->
        NavHost(
            navController = navController,
            startDestination = NavigationRoute.CHAT,
            modifier = Modifier.padding(paddingValues)
        ) {
            composable(NavigationRoute.CHAT) {
                ChatScreen()
            }

            composable(NavigationRoute.STORAGE) {
                StorageScreen()
            }

            composable(NavigationRoute.SETTINGS) {
                SettingsScreen()
            }

            composable(NavigationRoute.QUIZ) {
                QuizScreen()
            }

            composable(NavigationRoute.VOICE) {
                VoiceAssistantScreen()
            }
        }
    }
}

@Composable
fun BottomNavigationBar(navController: NavController) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    // Match iOS tab order and icons exactly: Chat, Storage, Settings, Quiz, Voice
    val items = listOf(
        BottomNavItem(
            route = NavigationRoute.CHAT,
            label = "Chat",
            icon = Icons.Filled.Chat,
            selectedIcon = Icons.Filled.Chat
        ),
        BottomNavItem(
            route = NavigationRoute.STORAGE,
            label = "Storage",
            icon = Icons.Outlined.Storage,
            selectedIcon = Icons.Filled.Storage
        ),
        BottomNavItem(
            route = NavigationRoute.SETTINGS,
            label = "Settings",
            icon = Icons.Outlined.Settings,
            selectedIcon = Icons.Filled.Settings
        ),
        BottomNavItem(
            route = NavigationRoute.QUIZ,
            label = "Quiz",
            icon = Icons.Outlined.Quiz,
            selectedIcon = Icons.Filled.Quiz
        ),
        BottomNavItem(
            route = NavigationRoute.VOICE,
            label = "Voice",
            icon = Icons.Outlined.Mic,
            selectedIcon = Icons.Filled.Mic
        )
    )

    NavigationBar {
        items.forEach { item ->
            val selected = currentDestination?.hierarchy?.any { it.route == item.route } == true

            NavigationBarItem(
                icon = {
                    Icon(
                        imageVector = if (selected) item.selectedIcon else item.icon,
                        contentDescription = item.label
                    )
                },
                label = { Text(item.label) },
                selected = selected,
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
                }
            )
        }
    }
}

/**
 * Navigation routes matching iOS tabs
 */
object NavigationRoute {
    const val CHAT = "chat"
    const val STORAGE = "storage"
    const val SETTINGS = "settings"
    const val QUIZ = "quiz"
    const val VOICE = "voice"
}

/**
 * Bottom navigation item data
 */
data class BottomNavItem(
    val route: String,
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector = icon
)
