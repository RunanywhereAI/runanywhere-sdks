package com.runanywhere.runanywhereai.ui.navigation

import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.toRoute
import com.runanywhere.runanywhereai.ui.screens.chat.ChatScreen
import com.runanywhere.runanywhereai.ui.screens.chat.ChatViewModel
import com.runanywhere.runanywhereai.ui.screens.benchmark.BenchmarkDetailScreen
import com.runanywhere.runanywhereai.ui.screens.benchmark.BenchmarkScreen
import com.runanywhere.runanywhereai.ui.screens.cloud.CloudProvidersScreen
import com.runanywhere.runanywhereai.ui.screens.more.MoreScreen
import com.runanywhere.runanywhereai.ui.screens.rag.RagScreen
import com.runanywhere.runanywhereai.ui.screens.settings.SettingsScreen
import com.runanywhere.runanywhereai.ui.screens.solutions.SolutionsScreen
import com.runanywhere.runanywhereai.ui.screens.stt.SttScreen
import com.runanywhere.runanywhereai.ui.screens.tools.ToolsScreen
import com.runanywhere.runanywhereai.ui.screens.tts.TtsScreen
import com.runanywhere.runanywhereai.ui.screens.vad.VadScreen
import com.runanywhere.runanywhereai.ui.screens.vision.VisionScreen
import com.runanywhere.runanywhereai.ui.screens.voice.VoiceScreen
import com.runanywhere.runanywhereai.ui.theme.AppMotion

@Composable
fun AppNavHost(
    navController: NavHostController,
    chatViewModel: ChatViewModel,
    onOpenModels: () -> Unit,
    onOpenVision: () -> Unit,
    onOpenVoice: () -> Unit,
    onOpenAdvanced: () -> Unit,
    modifier: Modifier = Modifier,
) {
    NavHost(
        navController = navController,
        startDestination = Chat,
        modifier = modifier,
        enterTransition = {
            slideInHorizontally(tween(AppMotion.DURATION_MEDIUM, easing = AppMotion.EaseOut)) { it / 4 } +
                fadeIn(tween(AppMotion.DURATION_MEDIUM, easing = AppMotion.EaseOut))
        },
        exitTransition = {
            slideOutHorizontally(tween(AppMotion.DURATION_MEDIUM, easing = AppMotion.EaseIn)) { -it / 4 } +
                fadeOut(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseIn))
        },
        popEnterTransition = {
            slideInHorizontally(tween(AppMotion.DURATION_MEDIUM, easing = AppMotion.EaseOut)) { -it / 4 } +
                fadeIn(tween(AppMotion.DURATION_MEDIUM, easing = AppMotion.EaseOut))
        },
        popExitTransition = {
            slideOutHorizontally(tween(AppMotion.DURATION_MEDIUM, easing = AppMotion.EaseIn)) { it / 4 } +
                fadeOut(tween(AppMotion.DURATION_SHORT, easing = AppMotion.EaseIn))
        },
    ) {
        composable<Chat> {
            ChatScreen(
                viewModel = chatViewModel,
                onOpenVision = onOpenVision,
                onOpenVoice = onOpenVoice,
                onOpenAdvanced = onOpenAdvanced,
            )
        }
        composable<Voice> { VoiceScreen() }
        composable<More> { MoreScreen(onNavigate = { navController.navigate(it) }) }
        composable<Settings> {
            SettingsScreen(
                onOpenModels = onOpenModels,
                onOpenAdvanced = onOpenAdvanced,
            )
        }
        composable<Tools> { ToolsScreen() }
        composable<Tts> { TtsScreen() }
        composable<Stt> { SttScreen() }
        composable<Vad> { VadScreen() }
        composable<Vision> { entry ->
            VisionScreen(openLiveCamera = entry.toRoute<Vision>().openLiveCamera)
        }
        composable<Documents> { RagScreen() }
        composable<Solutions> { SolutionsScreen() }
        composable<CloudProviders> { CloudProvidersScreen() }
        composable<Benchmarks> {
            BenchmarkScreen(onOpenDetail = { navController.navigate(BenchmarkDetail(it)) })
        }
        composable<BenchmarkDetail> { entry ->
            BenchmarkDetailScreen(runId = entry.toRoute<BenchmarkDetail>().runId)
        }
    }
}
