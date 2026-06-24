package com.runanywhere.sdk.runanywhereainpu

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.sdk.runanywhereainpu.ui.screens.HomeScreen
import com.runanywhere.sdk.runanywhereainpu.ui.screens.LlmScreen
import com.runanywhere.sdk.runanywhereainpu.ui.screens.ModelsScreen
import com.runanywhere.sdk.runanywhereainpu.ui.screens.SttScreen
import com.runanywhere.sdk.runanywhereainpu.ui.screens.TtsScreen
import com.runanywhere.sdk.runanywhereainpu.ui.screens.VlmScreen
import com.runanywhere.sdk.runanywhereainpu.ui.theme.RunAnywhereAiNPUTheme
import com.runanywhere.sdk.runanywhereainpu.ui.theme.Spacing

/** App navigation destinations. */
enum class Screen(val title: String) {
    Home("RunAnywhere NPU"),
    Llm("Chat"),
    Vlm("Vision"),
    Stt("Speech to Text"),
    Tts("Text to Speech"),
    Models("Models"),
}

// Content is centred and capped on wide screens (tablets / landscape / split
// screen) instead of stretching edge to edge.
private val ContentMaxWidth = 640.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RunAnywhereAiNPUTheme {
                AppRoot()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppRoot(vm: AppViewModel = viewModel()) {
    val state by vm.state.collectAsState()
    var screen by rememberSaveable { mutableStateOf(Screen.Home) }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(screen.title) },
                navigationIcon = {
                    if (screen != Screen.Home) {
                        IconButton(onClick = { screen = Screen.Home }) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    titleContentColor = MaterialTheme.colorScheme.onBackground,
                ),
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            Box(Modifier.fillMaxSize().widthIn(max = ContentMaxWidth)) {
                when {
                    state.bootstrapping -> Bootstrapping()
                    else -> when (screen) {
                        Screen.Home -> HomeScreen(state = state, onNavigate = { screen = it })
                        Screen.Llm -> LlmScreen()
                        Screen.Vlm -> VlmScreen()
                        Screen.Stt -> SttScreen()
                        Screen.Tts -> TtsScreen()
                        Screen.Models -> ModelsScreen()
                    }
                }
            }
        }
    }
}

@Composable
private fun Bootstrapping() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Text(
                "Detecting NPU…",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = Spacing.md),
            )
        }
    }
}
