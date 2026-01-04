package com.runanywhere.runanywhereai

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import com.runanywhere.runanywhereai.presentation.common.InitializationErrorView
import com.runanywhere.runanywhereai.presentation.common.InitializationLoadingView
import com.runanywhere.runanywhereai.presentation.navigation.AppNavigation
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme
import kotlinx.coroutines.launch

/**
 * Main Activity for RunAnywhere AI app.
 * Matches iOS RunAnywhereAIApp.swift pattern exactly:
 * - Shows InitializationLoadingView while SDK initializes
 * - Shows InitializationErrorView if initialization fails (with retry)
 * - Shows ContentView (AppNavigation) when SDK is ready
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Setup edge-to-edge display
        enableEdgeToEdge()

        setContent {
            RunAnywhereAITheme {
                MainAppContent()
            }
        }
    }

    /**
     * Main content composable with initialization state handling.
     * Matches iOS pattern:
     * - if isSDKInitialized -> ContentView
     * - else if initializationError -> InitializationErrorView
     * - else -> InitializationLoadingView
     */
    @Composable
    private fun MainAppContent() {
        val app = application as RunAnywhereApplication
        val initState by app.initializationState.collectAsState()
        val scope = rememberCoroutineScope()

        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
        ) {
            when (initState) {
                is SDKInitializationState.Loading -> {
                    InitializationLoadingView()
                }

                is SDKInitializationState.Error -> {
                    val error = (initState as SDKInitializationState.Error).error
                    InitializationErrorView(
                        error = error,
                        onRetry = {
                            scope.launch {
                                app.retryInitialization()
                            }
                        },
                    )
                }

                is SDKInitializationState.Ready -> {
                    Log.i("MainActivity", "App is ready to use!")
                    AppNavigation()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Resume any active voice sessions if needed
        // TODO: Implement when voice pipeline service is available
    }

    override fun onPause() {
        super.onPause()
        // Pause voice sessions to save battery
        // TODO: Implement when voice pipeline service is available
    }
}
