package com.runanywhere.runanywhereai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.runanywhere.runanywhereai.ui.screens.system_ui.AppScaffold
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // The manifest points this activity at Theme.RunAnywhereAI.Starting so the
        // cold-start window shows the brand mark instead of the platform default.
        // Hand back to the running theme now that Compose is about to draw —
        // otherwise the launch window's mark would sit behind every screen for the
        // life of the process.
        setTheme(R.style.Theme_RunAnywhereAI)
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RunAnywhereAITheme {
                AppScaffold()
            }
        }
    }
}
