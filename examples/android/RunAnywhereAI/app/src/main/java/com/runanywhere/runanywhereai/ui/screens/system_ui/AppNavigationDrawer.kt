package com.runanywhere.runanywhereai.ui.screens.system_ui

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.PermanentDrawerSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination
import androidx.navigation.NavHostController
import com.runanywhere.runanywhereai.ui.navigation.TopLevelDestination
import com.runanywhere.runanywhereai.ui.navigation.isSelected
import com.runanywhere.runanywhereai.ui.navigation.navigateTopLevel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens

// Fixed side panel for expanded (tablet) widths. Same destinations as the bottom bar.
@Composable
fun AppNavigationDrawer(
    navController: NavHostController,
    destination: NavDestination?,
) {
    val dimens = LocalDimens.current
    PermanentDrawerSheet(
        modifier = Modifier
            .fillMaxHeight()
            .width(dimens.navDrawerWidth),
        drawerContainerColor = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Spacer(Modifier.height(dimens.spacingXl))
        Text(
            text = "RunAnywhere",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
        )
        Spacer(Modifier.height(dimens.spacingSm))
        TopLevelDestination.entries.forEach { item ->
            val selected = destination.isSelected(item.route)
            NavigationDrawerItem(
                label = { Text(item.label) },
                selected = selected,
                onClick = { navController.navigateTopLevel(item.route) },
                icon = {
                    Icon(
                        imageVector = if (selected) item.selectedIcon else item.icon,
                        contentDescription = null,
                    )
                },
                modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding),
            )
        }
    }
}
