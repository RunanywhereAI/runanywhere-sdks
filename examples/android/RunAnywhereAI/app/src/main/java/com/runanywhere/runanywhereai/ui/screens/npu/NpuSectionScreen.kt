package com.runanywhere.runanywhereai.ui.screens.npu

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.screens.npu.screens.HomeScreen
import com.runanywhere.runanywhereai.ui.screens.npu.screens.LlmScreen
import com.runanywhere.runanywhereai.ui.screens.npu.screens.SttScreen
import com.runanywhere.runanywhereai.ui.screens.npu.screens.TtsScreen
import com.runanywhere.runanywhereai.ui.screens.npu.screens.VlmScreen
import com.runanywhere.runanywhereai.ui.screens.npu.theme.RunAnywhereAiNPUTheme
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing

/** NPU section navigation destinations. */
enum class Screen(val title: String) {
    Home("RunAnywhere NPU"),
    Llm("Chat"),
    Vlm("Vision"),
    Stt("Speech to Text"),
    Tts("Text to Speech"),
}

private val ContentMaxWidth = 640.dp

/**
 * Self-contained NPU (QHexRT) section, hosted from the app's More → NPU entry.
 * Wraps its own enum-nav + the standalone NPU theme so it renders exactly like
 * the dedicated NPU app without disturbing the host app.
 *
 * @param onExit pop back to the host app (invoked from the NPU Home back arrow).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NpuSectionScreen(onExit: () -> Unit, vm: AppViewModel = viewModel()) {
    val state by vm.state.collectAsState()
    // Shared across every NPU screen (same nav owner), so downloads survive
    // navigation. Fed the probed Hexagon arch so each screen only offers
    // bundles that can actually load on this chip.
    val modelsVm: NpuModelsViewModel = viewModel()
    LaunchedEffect(state.npu?.arch) { modelsVm.setDeviceArch(state.npu?.arch) }
    var screen by rememberSaveable { mutableStateOf(Screen.Home) }

    RunAnywhereAiNPUTheme {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            topBar = {
                TopAppBar(
                    title = { Text(screen.title) },
                    navigationIcon = {
                        IconButton(onClick = { if (screen == Screen.Home) onExit() else screen = Screen.Home }) {
                            Icon(RACIcons.Outline.ArrowLeft, contentDescription = "Back")
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
                            Screen.Llm -> LlmScreen(modelsVm)
                            Screen.Vlm -> VlmScreen(modelsVm)
                            Screen.Stt -> SttScreen(modelsVm)
                            Screen.Tts -> TtsScreen(modelsVm)
                        }
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
