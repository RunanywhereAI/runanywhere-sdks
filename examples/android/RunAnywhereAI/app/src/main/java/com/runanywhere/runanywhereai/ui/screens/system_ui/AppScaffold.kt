package com.runanywhere.runanywhereai.ui.screens.system_ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PermanentNavigationDrawer
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.navigation.AppNavHost
import com.runanywhere.runanywhereai.ui.screens.chat.ConversationHistorySheet
import com.runanywhere.runanywhereai.ui.screens.intro.IntroScreen
import com.runanywhere.runanywhereai.ui.screens.lora.LoraSheet
import com.runanywhere.runanywhereai.ui.screens.lora.LoraViewModel
import com.runanywhere.runanywhereai.ui.screens.chat.ChatViewModel
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.util.LocalIsExpandedLayout
import com.runanywhere.runanywhereai.util.isExpandedScreen

// Single app frame: route-dispatched chrome + NavHost. Bottom bar on compact widths,
// side nav rail on expanded (tablet) widths.
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

    val isExpanded = isExpandedScreen()
    val showNav = destination != null

    CompositionLocalProvider(LocalIsExpandedLayout provides isExpanded) {
        val frame: @Composable () -> Unit = {
            Scaffold(
                modifier = Modifier.fillMaxSize(),
                topBar = {
                    if (showNav) {
                        AppTopBar(
                            destination = destination,
                            model = GlobalState.model.loaded,
                            generating = chatViewModel.isGenerating,
                            loraActive = GlobalState.lora.isActive,
                            onModelClick = { showModelSheet = true },
                            onNewChat = chatViewModel::clearChat,
                            onHistory = { showHistorySheet = true },
                            onLora = { showLoraSheet = true },
                        )
                    }
                },
                // Bottom bar only on compact widths; expanded uses the rail (added in the Row below).
                bottomBar = {
                    if (showNav && !isExpanded) AppBottomBar(navController, destination)
                },
            ) { innerPadding ->
                AppNavHost(
                    navController = navController,
                    chatViewModel = chatViewModel,
                    modifier = Modifier
                        .padding(innerPadding)
                        .consumeWindowInsets(innerPadding),
                )
            }
        }

        Box(modifier = Modifier.fillMaxSize()) {
            if (showNav && isExpanded) {
                PermanentNavigationDrawer(
                    drawerContent = { AppNavigationDrawer(navController, destination) },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    frame()
                }
            } else {
                frame()
            }

            // Startup splash gate: covers the app until SDK setup reports ready, so the
            // back stack roots at Chat (not a popped Intro destination) from the first frame.
            if (!GlobalState.ready) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    IntroScreen()
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
    }
}
