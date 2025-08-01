package com.runanywhere.runanywhereai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.runanywhere.runanywhereai.ui.chat.ChatScreen
import com.runanywhere.runanywhereai.ui.models.ModelsScreen
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme
import com.runanywhere.sdk.RunAnywhereSDK

class MainActivity : ComponentActivity() {
    private val runAnywhereSDK = RunAnywhereSDK()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize the SDK
        runAnywhereSDK.initialize("demo-api-key")

        enableEdgeToEdge()
        setContent {
            RunAnywhereAITheme {
                RunAnywhereApp()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RunAnywhereApp() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    icon = { Icon(Icons.Default.Email, contentDescription = "Chat") },
                    label = { Text("Chat") },
                    selected = currentRoute == "chat",
                    onClick = {
                        navController.navigate("chat") {
                            popUpTo(navController.graph.startDestinationId)
                            launchSingleTop = true
                        }
                    }
                )
                NavigationBarItem(
                    icon = { Icon(Icons.Default.List, contentDescription = "Models") },
                    label = { Text("Models") },
                    selected = currentRoute == "models",
                    onClick = {
                        navController.navigate("models") {
                            popUpTo(navController.graph.startDestinationId)
                            launchSingleTop = true
                        }
                    }
                )
                NavigationBarItem(
                    icon = { Icon(Icons.Default.Info, contentDescription = "About") },
                    label = { Text("About") },
                    selected = currentRoute == "about",
                    onClick = {
                        navController.navigate("about") {
                            popUpTo(navController.graph.startDestinationId)
                            launchSingleTop = true
                        }
                    }
                )
            }
        }
    ) { paddingValues ->
        NavHost(
            navController = navController,
            startDestination = "chat",
            modifier = Modifier.padding(paddingValues)
        ) {
            composable("chat") {
                ChatScreen(
                    onNavigateToModels = {
                        navController.navigate("models")
                    }
                )
            }
            composable("models") {
                ModelsScreen(
                    onNavigateBack = {
                        navController.navigateUp()
                    }
                )
            }
            composable("about") {
                AboutScreen()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen() {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("About") }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Card(
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "RunAnywhere AI",
                        style = MaterialTheme.typography.headlineMedium
                    )
                    Text(
                        text = "SDK Version: ${RunAnywhereSDK.VERSION}",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = "On-device LLM inference demo app showcasing MediaPipe and ONNX Runtime integration.",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }

            Card(
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Features",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text("• On-device LLM inference")
                    Text("• Multiple framework support (MediaPipe, ONNX)")
                    Text("• Model management and downloading")
                    Text("• Real-time streaming responses")
                    Text("• Privacy-focused - no data leaves device")
                }
            }

            Card(
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Supported Models",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text("• Gemma 2B (MediaPipe)")
                    Text("• Phi-2 (MediaPipe)")
                    Text("• TinyLlama 1.1B (ONNX)")
                    Text("• More models coming soon...")
                }
            }
        }
    }
}
