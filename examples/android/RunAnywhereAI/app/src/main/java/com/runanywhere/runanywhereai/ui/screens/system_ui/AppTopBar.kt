package com.runanywhere.runanywhereai.ui.screens.system_ui

import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import com.runanywhere.runanywhereai.ui.navigation.Solutions
import com.runanywhere.runanywhereai.ui.navigation.Stt
import com.runanywhere.runanywhereai.ui.navigation.Tools
import com.runanywhere.runanywhereai.ui.navigation.Tts
import com.runanywhere.runanywhereai.ui.navigation.Vad
import com.runanywhere.runanywhereai.ui.navigation.Vision
import com.runanywhere.runanywhereai.ui.navigation.Voice
import com.runanywhere.runanywhereai.ui.screens.chat.ChatTopBar
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo

// Pure route dispatcher: picks each screen's own top bar. No UI defined here.
@Composable
fun AppTopBar(
    destination: NavDestination?,
    model: RAModelInfo?,
    conversationModelName: String?,
    generating: Boolean,
    loraActive: Boolean,
    hasMessages: Boolean,
    onModelClick: () -> Unit,
    onNewChat: () -> Unit,
    onHistory: () -> Unit,
    onLora: () -> Unit,
    onDetails: () -> Unit,
    onMenu: () -> Unit,
    onNavigateBack: () -> Unit,
    showMenu: Boolean,
    canNavigateBack: Boolean,
) {
    when {
        destination == null -> Unit
        destination.hasRoute<Chat>() -> ChatTopBar(
            model = model,
            conversationModelName = conversationModelName,
            generating = generating,
            loraActive = loraActive,
            hasMessages = hasMessages,
            onModelClick = onModelClick,
            onNewChat = onNewChat,
            onHistory = onHistory,
            onLora = onLora,
            onDetails = onDetails,
            onMenu = onMenu,
            showMenu = showMenu,
        )
        destination.hasRoute<Voice>() -> StandardTopBar("Talk", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<More>() -> StandardTopBar("Advanced", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<Settings>() -> StandardTopBar("Settings", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<Tools>() -> StandardTopBar("Web & tools", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<Tts>() -> StandardTopBar("Read aloud", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<Stt>() -> StandardTopBar("Transcription", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<Vad>() -> StandardTopBar("Voice activity", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<Vision>() -> StandardTopBar("Images & live", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<Documents>() -> StandardTopBar("Documents", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<Solutions>() -> StandardTopBar("Solutions", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<CloudProviders>() -> StandardTopBar("Cloud providers", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<Benchmarks>() -> StandardTopBar("Benchmarks", showMenu, onMenu, canNavigateBack, onNavigateBack)
        destination.hasRoute<BenchmarkDetail>() -> StandardTopBar("Run details", showMenu, onMenu, canNavigateBack, onNavigateBack)
        else -> Unit
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StandardTopBar(
    title: String,
    showMenu: Boolean = false,
    onMenu: () -> Unit = {},
    canNavigateBack: Boolean = false,
    onNavigateBack: () -> Unit = {},
) {
    CenterAlignedTopAppBar(
        title = { Text(title) },
        navigationIcon = {
            when {
                canNavigateBack -> {
                    IconButton(onClick = onNavigateBack) {
                        Icon(RACIcons.Outline.ChevronLeft, contentDescription = "Go back")
                    }
                }
                showMenu -> {
                    IconButton(onClick = onMenu) {
                        Icon(RACIcons.Outline.Menu, contentDescription = "Open menu")
                    }
                }
            }
        },
    )
}
