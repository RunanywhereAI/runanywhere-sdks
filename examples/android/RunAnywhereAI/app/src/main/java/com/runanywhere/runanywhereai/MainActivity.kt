package com.runanywhere.runanywhereai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.runanywhere.runanywhereai.presentation.navigation.AppNavigation
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme

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

    @Composable
    private fun MainAppContent() {
        // Handle system bars
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background
        ) {
            AppNavigation()
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
