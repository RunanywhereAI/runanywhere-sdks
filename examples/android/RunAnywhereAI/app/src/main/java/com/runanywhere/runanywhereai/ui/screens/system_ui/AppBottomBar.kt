package com.runanywhere.runanywhereai.ui.screens.system_ui

import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.navigation.NavDestination
import androidx.navigation.NavHostController
import com.runanywhere.runanywhereai.ui.navigation.TopLevelDestination
import com.runanywhere.runanywhereai.ui.navigation.isSelected
import com.runanywhere.runanywhereai.ui.navigation.navigateTopLevel

// Bottom tab bar — compact widths.
@Composable
fun AppBottomBar(
    navController: NavHostController,
    destination: NavDestination?,
) {
    NavigationBar {
        TopLevelDestination.entries.forEach { item ->
            val selected = destination.isSelected(item.route)
            NavigationBarItem(
                selected = selected,
                onClick = { navController.navigateTopLevel(item.route) },
                icon = {
                    Icon(
                        imageVector = if (selected) item.selectedIcon else item.icon,
                        contentDescription = item.label,
                    )
                },
                label = { Text(item.label) },
            )
        }
    }
}
