package com.runanywhere.runanywhereai.navigation

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
import com.runanywhere.runanywhereai.ui.screens.BenchmarkDashboardScreen
import com.runanywhere.runanywhereai.ui.screens.BenchmarkDetailScreen
import com.runanywhere.runanywhereai.ui.screens.ChatScreen
import com.runanywhere.runanywhereai.ui.screens.LoraManagerScreen
import com.runanywhere.runanywhereai.ui.screens.MoreHubScreen
import com.runanywhere.runanywhereai.ui.screens.DocumentRagScreen
import com.runanywhere.runanywhereai.ui.screens.SettingsScreen
import com.runanywhere.runanywhereai.ui.screens.SpeechToTextScreen
import com.runanywhere.runanywhereai.ui.screens.TextToSpeechScreen
import com.runanywhere.runanywhereai.ui.screens.VisionHubScreen
import com.runanywhere.runanywhereai.ui.screens.VlmScreen
import com.runanywhere.runanywhereai.ui.screens.VoiceAssistantScreen
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.viewmodels.ChatViewModel
import com.runanywhere.runanywhereai.viewmodels.ModelSelectionViewModel

@Composable
fun AppNavHost(
    navController: NavHostController,
    chatViewModel: ChatViewModel,
    modelSelectionViewModel: ModelSelectionViewModel,
    modifier: Modifier = Modifier,
) {
    NavHost(
        navController = navController,
        startDestination = Route.Chat,
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
        // Bottom nav tabs
        composable<Route.Chat> { ChatScreen(chatViewModel = chatViewModel) }
        composable<Route.Vision> { VisionHubScreen(onNavigateToVlm = { navController.navigate(Route.Vlm) }) }
        composable<Route.Voice> { VoiceAssistantScreen() }
        composable<Route.More> {
            MoreHubScreen(
                onNavigateToStt = { navController.navigate(Route.Stt) },
                onNavigateToTts = { navController.navigate(Route.Tts) },
                onNavigateToRag = { navController.navigate(Route.Rag) },
                onNavigateToBenchmarks = { navController.navigate(Route.Benchmarks) },
            )
        }
        composable<Route.Settings> { SettingsScreen() }

        // Secondary screens
        composable<Route.Vlm> { VlmScreen(onBack = { navController.popBackStack() }) }
        composable<Route.Stt> { SpeechToTextScreen(onBack = { navController.popBackStack() }) }
        composable<Route.Tts> { TextToSpeechScreen(onBack = { navController.popBackStack() }) }
        composable<Route.Rag> { DocumentRagScreen(onBack = { navController.popBackStack() }) }
        composable<Route.LoraManager> { LoraManagerScreen(onBack = { navController.popBackStack() }) }
        composable<Route.Benchmarks> {
            BenchmarkDashboardScreen(
                onBack = { navController.popBackStack() },
                onNavigateToDetail = { runId -> navController.navigate(Route.BenchmarkDetail(runId)) },
            )
        }
        composable<Route.BenchmarkDetail> { entry ->
            val detail = entry.toRoute<Route.BenchmarkDetail>()
            BenchmarkDetailScreen(
                runId = detail.runId,
                onBack = { navController.popBackStack() },
            )
        }
    }
}
