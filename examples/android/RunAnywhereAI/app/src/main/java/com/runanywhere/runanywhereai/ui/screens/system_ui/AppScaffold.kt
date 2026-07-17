package com.runanywhere.runanywhereai.ui.screens.system_ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.PermanentNavigationDrawer
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.rememberDrawerState
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.navigation.AppNavHost
import com.runanywhere.runanywhereai.ui.navigation.Chat
import com.runanywhere.runanywhereai.ui.navigation.More
import com.runanywhere.runanywhereai.ui.navigation.Settings
import com.runanywhere.runanywhereai.ui.navigation.Vision
import com.runanywhere.runanywhereai.ui.navigation.Voice
import com.runanywhere.runanywhereai.ui.navigation.isConsumerTopLevel
import com.runanywhere.runanywhereai.ui.navigation.isSelected
import com.runanywhere.runanywhereai.ui.navigation.navigateTopLevel
import com.runanywhere.runanywhereai.ui.screens.chat.ChatDetailsSheet
import com.runanywhere.runanywhereai.ui.screens.chat.ConversationHistorySheet
import com.runanywhere.runanywhereai.ui.screens.intro.InitErrorScreen
import com.runanywhere.runanywhereai.ui.screens.intro.IntroScreen
import com.runanywhere.runanywhereai.ui.screens.lora.LoraSheet
import com.runanywhere.runanywhereai.ui.screens.lora.LoraViewModel
import com.runanywhere.runanywhereai.ui.screens.chat.ChatViewModel
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.util.LocalIsExpandedLayout
import com.runanywhere.runanywhereai.util.isExpandedScreen
import kotlinx.coroutines.launch

// Single app frame: route-dispatched chrome + NavHost. Compact widths use a
// modal drawer; expanded layouts keep the same IA visible as a side drawer.
@Composable
fun AppScaffold() {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val destination = backStackEntry?.destination

    // Hoisted at activity scope so the chat top bar and chat screen share one instance.
    val chatViewModel: ChatViewModel = viewModel()
    val modelViewModel: ModelSelectionViewModel =
        viewModel(factory = ModelSelectionViewModel.Factory(ModelSelectionContext.LLM))
    val loraViewModel: LoraViewModel = viewModel()
    var showModelSheet by remember { mutableStateOf(false) }
    var showHistorySheet by remember { mutableStateOf(false) }
    var showLoraSheet by remember { mutableStateOf(false) }
    var showDetailsSheet by remember { mutableStateOf(false) }
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()

    val isExpanded = isExpandedScreen()
    val showNav = destination != null
    val previousDestination = navController.previousBackStackEntry?.destination
    val canNavigateBack = destination != null &&
        previousDestination != null &&
        (!destination.isConsumerTopLevel() || !previousDestination.isSelected(Chat))
    val startNewChat = {
        chatViewModel.clearChat()
        navController.navigateTopLevel(Chat)
    }

    CompositionLocalProvider(LocalIsExpandedLayout provides isExpanded) {
        val frame: @Composable () -> Unit = {
            Scaffold(
                modifier = Modifier.fillMaxSize(),
                topBar = {
                    if (showNav) {
                        AppTopBar(
                            destination = destination,
                            model = GlobalState.model.loaded,
                            conversationModelName = chatViewModel.conversationModelName,
                            generating = chatViewModel.isGenerating,
                            loraActive = GlobalState.lora.isActive,
                            hasMessages = chatViewModel.messages.isNotEmpty(),
                            onModelClick = { showModelSheet = true },
                            onNewChat = chatViewModel::clearChat,
                            onHistory = { showHistorySheet = true },
                            onLora = { showLoraSheet = true },
                            onDetails = { showDetailsSheet = true },
                            onMenu = { scope.launch { drawerState.open() } },
                            onNavigateBack = { navController.popBackStack() },
                            showMenu = !isExpanded,
                            canNavigateBack = canNavigateBack,
                        )
                    }
                },
            ) { innerPadding ->
                AppNavHost(
                    navController = navController,
                    chatViewModel = chatViewModel,
                    onOpenModels = { showModelSheet = true },
                    isModelSheetVisible = showModelSheet,
                    // This is an explicit request for live mode. Do not restore a
                    // previously saved photo-mode Vision destination over its argument.
                    onOpenVision = {
                        navController.navigateTopLevel(
                            Vision(openLiveCamera = true),
                            restoreState = false,
                        )
                    },
                    onOpenVoice = { navController.navigateTopLevel(Voice) },
                    onOpenAdvanced = { navController.navigateTopLevel(More) },
                    modifier = Modifier
                        .padding(innerPadding)
                        .consumeWindowInsets(innerPadding),
                )
            }
        }

        Box(modifier = Modifier.fillMaxSize()) {
            if (showNav && isExpanded) {
                PermanentNavigationDrawer(
                    drawerContent = {
                        AppNavigationDrawer(
                            destination = destination,
                            onNewChat = startNewChat,
                            onHistory = { showHistorySheet = true },
                            onNavigate = { navController.navigateTopLevel(it) },
                            permanent = true,
                        )
                    },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    frame()
                }
            } else {
                ModalNavigationDrawer(
                    drawerState = drawerState,
                    gesturesEnabled = showNav,
                    drawerContent = {
                        AppNavigationDrawer(
                            destination = destination,
                            onNewChat = startNewChat,
                            onHistory = { showHistorySheet = true },
                            onNavigate = { navController.navigateTopLevel(it) },
                            onDismiss = { afterClose ->
                                scope.launch {
                                    drawerState.close()
                                    afterClose()
                                }
                            },
                            permanent = false,
                        )
                    },
                ) {
                    frame()
                }
            }

            // Startup splash gate: covers the app until SDK setup reports ready, so the
            // back stack roots at Chat (not a popped Intro destination) from the first frame.
            // Mirrors iOS: a failed setup swaps the splash for an error view with retry.
            if (!GlobalState.ready) {
                val context = LocalContext.current
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    val error = GlobalState.initError
                    if (error != null) {
                        InitErrorScreen(
                            message = error,
                            onRetry = {
                                (context.applicationContext as RunAnywhereApplication).retrySdkSetup()
                            },
                        )
                    } else {
                        IntroScreen()
                    }
                }
            }
        }

        if (showModelSheet) {
            ModelSelectionSheet(
                viewModel = modelViewModel,
                onDismiss = { showModelSheet = false },
            )
        }

        if (showLoraSheet) {
            LoraSheet(viewModel = loraViewModel, onDismiss = { showLoraSheet = false })
        }

        if (showHistorySheet) {
            ConversationHistorySheet(
                onSelect = {
                    chatViewModel.loadConversation(it)
                    showHistorySheet = false
                },
                onDelete = chatViewModel::deleteConversation,
                onRename = chatViewModel::rename,
                onTogglePin = chatViewModel::setPinned,
                onDismiss = { showHistorySheet = false },
            )
        }

        if (showDetailsSheet) {
            ChatDetailsSheet(
                messages = chatViewModel.messages,
                createdAt = chatViewModel.conversationCreatedAt.takeIf { it > 0 },
                onDismiss = { showDetailsSheet = false },
            )
        }
    }
}
