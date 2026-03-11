package com.runanywhere.runanywhereai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.runanywhere.runanywhereai.models.DialogState
import com.runanywhere.runanywhereai.navigation.AppNavHost
import com.runanywhere.runanywhereai.navigation.TopBarType
import com.runanywhere.runanywhereai.navigation.TopLevelDestination
import com.runanywhere.runanywhereai.navigation.resolveTopBar
import com.runanywhere.runanywhereai.ui.components.ChatTopBar
import com.runanywhere.runanywhereai.ui.components.ConversationHistorySheet
import com.runanywhere.runanywhereai.ui.components.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereTheme
import com.runanywhere.runanywhereai.viewmodels.ChatViewModel
import com.runanywhere.runanywhereai.viewmodels.ModelSelectionViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RunAnywhereTheme {
                MainApp()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MainApp() {
    val navController = rememberNavController()
    val currentEntry by navController.currentBackStackEntryAsState()
    val currentDestination = currentEntry?.destination
    val topBarType = remember(currentEntry) { resolveTopBar(currentEntry) }

    // Hoisted ViewModels for Chat — shared between top bar and screen
    val chatViewModel: ChatViewModel = viewModel()
    val modelSelectionViewModel: ModelSelectionViewModel = viewModel()
    val chatUiState by chatViewModel.uiState.collectAsStateWithLifecycle()
    val modelState by modelSelectionViewModel.uiState.collectAsStateWithLifecycle()

    // Dialog state for model selection sheet (triggered from top bar)
    var dialogState by remember { mutableStateOf<DialogState>(DialogState.None) }

    // Hide bottom bar on secondary screens
    val showBottomBar = TopLevelDestination.entries.any { tab ->
        currentDestination?.hasRoute(tab.route::class) == true
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            when (topBarType) {
                is TopBarType.Chat -> {
                    val readyState = chatUiState as? com.runanywhere.runanywhereai.models.ChatUiState.Ready
                    ChatTopBar(
                        modelName = readyState?.loadedModelName,
                        isModelLoaded = readyState?.isModelLoaded == true,
                        hasActiveLoraAdapter = readyState?.hasActiveLoraAdapter == true,
                        onModelChipClick = {
                            modelSelectionViewModel.loadModels()
                            dialogState = DialogState.ModelSelection
                        },
                        onHistoryClick = {
                            dialogState = DialogState.ConversationList
                        },
                        onNewChatClick = {
                            chatViewModel.clearChat()
                        },
                    )
                }
                is TopBarType.Standard -> {
                    TopAppBar(
                        title = {
                            AnimatedContent(
                                targetState = topBarType.title,
                                transitionSpec = {
                                    (fadeIn(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseOut)) +
                                        slideInVertically(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseOut)) { it / 2 })
                                        .togetherWith(
                                            fadeOut(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseIn)) +
                                                slideOutVertically(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseIn)) { -it / 2 }
                                        )
                                },
                                label = "topBarTitle",
                            ) { title ->
                                Text(title)
                            }
                        },
                        navigationIcon = {
                            AnimatedVisibility(
                                visible = topBarType.showBack,
                                enter = fadeIn(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseOut)),
                                exit = fadeOut(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseIn)),
                            ) {
                                IconButton(onClick = { navController.popBackStack() }) {
                                    Icon(RAIcons.ChevronLeft, contentDescription = "Back")
                                }
                            }
                        },
                    )
                }
            }
        },
        bottomBar = {
            AnimatedVisibility(
                visible = showBottomBar,
                enter = slideInVertically(tween(AppMotion.DURATION_MEDIUM, easing = AppMotion.EaseOut)) { it } +
                    fadeIn(tween(AppMotion.DURATION_MEDIUM, easing = AppMotion.EaseOut)),
                exit = slideOutVertically(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseIn)) { it } +
                    fadeOut(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseIn)),
            ) {
                NavigationBar {
                    TopLevelDestination.entries.forEach { destination ->
                        val selected = currentDestination?.hasRoute(destination.route::class) == true

                        NavigationBarItem(
                            selected = selected,
                            onClick = {
                                navController.navigate(destination.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = {
                                Icon(
                                    imageVector = if (selected) destination.selectedIcon else destination.icon,
                                    contentDescription = destination.label,
                                )
                            },
                            label = { Text(destination.label) },
                        )
                    }
                }
            }
        },
    ) { innerPadding ->
        AppNavHost(
            navController = navController,
            chatViewModel = chatViewModel,
            modelSelectionViewModel = modelSelectionViewModel,
            modifier = Modifier
                .padding(innerPadding)
                .consumeWindowInsets(innerPadding),
        )
    }

    // Conversation History BottomSheet
    if (dialogState == DialogState.ConversationList) {
        val historyConversations by chatViewModel.conversations.collectAsStateWithLifecycle()
        val currentConvId = (chatUiState as? com.runanywhere.runanywhereai.models.ChatUiState.Ready)?.currentConversation?.id

        ConversationHistorySheet(
            conversations = historyConversations,
            currentConversationId = currentConvId,
            onDismiss = { dialogState = DialogState.None },
            onSelectConversation = { id ->
                chatViewModel.loadConversation(id)
            },
            onDeleteConversation = { id ->
                chatViewModel.deleteConversation(id)
            },
            onDeleteAllConversations = {
                chatViewModel.deleteAllConversations()
                dialogState = DialogState.None
            },
            onNewChat = {
                chatViewModel.clearChat()
            },
        )
    }

    // Model Selection BottomSheet (hosted at activity level, triggered from top bar)
    if (dialogState == DialogState.ModelSelection) {
        ModelSelectionSheet(
            state = modelState,
            onDismiss = { dialogState = DialogState.None },
            onSelectModel = { modelId ->
                modelSelectionViewModel.selectModel(modelId) { name, supportsLora ->
                    chatViewModel.onModelLoaded(name, supportsLora)
                }
                dialogState = DialogState.None
            },
            onDownloadModel = { modelId ->
                modelSelectionViewModel.downloadModel(modelId)
            },
            onCancelModelDownload = {
                modelSelectionViewModel.cancelModelDownload()
            },
            onLoadLora = { adapterId ->
                modelSelectionViewModel.loadLoraAdapter(adapterId)
            },
            onUnloadLora = { adapterId ->
                modelSelectionViewModel.unloadLoraAdapter(adapterId)
            },
            onDownloadLora = { entry ->
                modelSelectionViewModel.downloadLoraAdapter(entry)
            },
            onCancelLoraDownload = {
                modelSelectionViewModel.cancelLoraDownload()
            },
            isLoraDownloaded = { modelSelectionViewModel.isLoraDownloaded(it) },
            isLoraLoaded = { modelSelectionViewModel.isLoraLoaded(it) },
        )
    }
}
