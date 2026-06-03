package com.runanywhere.runanywhereai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.runanywhere.runanywhereai.ui.screens.system_ui.AppScaffold
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RunAnywhereAITheme {
                AppScaffold()
            }
        }
    }
}