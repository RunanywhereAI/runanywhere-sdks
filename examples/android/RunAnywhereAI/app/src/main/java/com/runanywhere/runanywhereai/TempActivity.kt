package com.runanywhere.runanywhereai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.runanywhere.runanywhereai.presentation.hybird.HybridRouterScreen
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme

class TempActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RunAnywhereAITheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    HybridRouterScreen(innerPadding)
                }
            }
        }
    }
}