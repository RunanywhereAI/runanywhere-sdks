package com.runanywhere.runanywhereai.presentation.components

import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Holds dynamic top bar state driven by the currently visible screen.
 * Provided via [LocalTopBarState] from the root Scaffold in AppNavigation.
 */
@Stable
class TopBarState {
    var title by mutableStateOf("")
    var showBack by mutableStateOf(false)
    var onBack by mutableStateOf<(() -> Unit)?>(null)
    var actions by mutableStateOf<(@Composable RowScope.() -> Unit)>({})
    var customTopBar by mutableStateOf<(@Composable () -> Unit)?>(null)
}

val LocalTopBarState = staticCompositionLocalOf<TopBarState> { error("No TopBarState provided") }

/**
 * Standard screens call this to configure the shared top bar.
 * Sets [TopBarState.customTopBar] to null so the default TopAppBar is used.
 */
@Composable
fun ConfigureTopBar(
    title: String,
    showBack: Boolean = false,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val state = LocalTopBarState.current
    SideEffect {
        state.title = title
        state.showBack = showBack
        state.onBack = onBack
        state.actions = actions
        state.customTopBar = null
    }
}

/**
 * Screens with a fully custom top bar (Chat, VLM) call this.
 * The root Scaffold renders [content] instead of the default TopAppBar.
 */
@Composable
fun ConfigureCustomTopBar(content: @Composable () -> Unit) {
    val state = LocalTopBarState.current
    SideEffect {
        state.customTopBar = content
    }
}
