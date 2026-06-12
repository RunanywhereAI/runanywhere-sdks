package com.runanywhere.runanywhereai.ui.screens.system_ui

import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.navigation.NavDestination
import androidx.navigation.NavDestination.Companion.hasRoute
import com.runanywhere.runanywhereai.ui.navigation.BenchmarkDetail
import com.runanywhere.runanywhereai.ui.navigation.Benchmarks
import com.runanywhere.runanywhereai.ui.navigation.Chat
import com.runanywhere.runanywhereai.ui.navigation.CloudProviders
import com.runanywhere.runanywhereai.ui.navigation.Documents
import com.runanywhere.runanywhereai.ui.navigation.More
import com.runanywhere.runanywhereai.ui.navigation.Settings
import com.runanywhere.runanywhereai.ui.navigation.Stt
import com.runanywhere.runanywhereai.ui.navigation.Tts
import com.runanywhere.runanywhereai.ui.navigation.Vision
import com.runanywhere.runanywhereai.ui.navigation.Voice
import com.runanywhere.runanywhereai.ui.screens.chat.ChatTopBar
import com.runanywhere.sdk.public.types.RAModelInfo

// Pure route dispatcher: picks each screen's own top bar. No UI defined here.
@Composable
fun AppTopBar(
    destination: NavDestination?,
    model: RAModelInfo?,
    generating: Boolean,
    loraActive: Boolean,
    onModelClick: () -> Unit,
    onNewChat: () -> Unit,
    onHistory: () -> Unit,
    onLora: () -> Unit,
) {
    when {
        destination == null -> Unit
        destination.hasRoute<Chat>() -> ChatTopBar(
            model = model,
            generating = generating,
            loraActive = loraActive,
            onModelClick = onModelClick,
            onNewChat = onNewChat,
            onHistory = onHistory,
            onLora = onLora,
        )
        destination.hasRoute<Voice>() -> StandardTopBar("Voice")
        destination.hasRoute<More>() -> StandardTopBar("More")
        destination.hasRoute<Settings>() -> StandardTopBar("Settings")
        destination.hasRoute<Tts>() -> StandardTopBar("Text to Speech")
        destination.hasRoute<Stt>() -> StandardTopBar("Speech to Text")
        destination.hasRoute<Vision>() -> StandardTopBar("Vision")
        destination.hasRoute<Documents>() -> StandardTopBar("Documents")
        destination.hasRoute<CloudProviders>() -> StandardTopBar("Cloud providers")
        destination.hasRoute<Benchmarks>() -> StandardTopBar("Benchmarks")
        destination.hasRoute<BenchmarkDetail>() -> StandardTopBar("Run details")
        else -> Unit
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StandardTopBar(title: String) {
    CenterAlignedTopAppBar(title = { Text(title) })
}