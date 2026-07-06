package com.runanywhere.runanywhereai.ui.screens.system_ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.PermanentDrawerSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination
import androidx.navigation.NavHostController
import com.runanywhere.runanywhereai.ui.navigation.ConsumerDestination
import com.runanywhere.runanywhereai.ui.navigation.ConsumerNavGroup
import com.runanywhere.runanywhereai.ui.navigation.isSelected
import com.runanywhere.runanywhereai.ui.navigation.navigateTopLevel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

@Composable
fun AppNavigationDrawer(
    navController: NavHostController,
    destination: NavDestination?,
    onModels: () -> Unit,
    onAdapters: () -> Unit,
    onDismiss: () -> Unit = {},
    permanent: Boolean = true,
) {
    val dimens = LocalDimens.current
    val modifier = Modifier
        .fillMaxHeight()
        .width(dimens.navDrawerWidth)

    if (permanent) {
        PermanentDrawerSheet(
            modifier = modifier,
            drawerContainerColor = MaterialTheme.colorScheme.surfaceContainer,
        ) {
            DrawerContent(navController, destination, onModels, onAdapters, onDismiss)
        }
    } else {
        ModalDrawerSheet(
            modifier = modifier,
            drawerContainerColor = MaterialTheme.colorScheme.surfaceContainer,
        ) {
            DrawerContent(navController, destination, onModels, onAdapters, onDismiss)
        }
    }
}

@Composable
private fun DrawerContent(
    navController: NavHostController,
    destination: NavDestination?,
    onModels: () -> Unit,
    onAdapters: () -> Unit,
    onDismiss: () -> Unit,
) {
    val dimens = LocalDimens.current
    Column(
        modifier = Modifier
            .fillMaxHeight()
            .padding(vertical = dimens.spacingLg),
    ) {
        DrawerHeader()
        Spacer(Modifier.height(dimens.spacingMd))

        ConsumerNavGroup.entries.forEach { group ->
            DrawerSectionLabel(group.title)
            ConsumerDestination.entries
                .filter { it.group == group }
                .forEach { item ->
                    val selected = destination.isSelected(item.route)
                    DrawerRouteItem(
                        label = item.label,
                        description = item.description,
                        icon = if (selected) item.selectedIcon else item.icon,
                        selected = selected,
                        onClick = {
                            onDismiss()
                            navController.navigateTopLevel(item.route)
                        },
                    )
                }
            if (group == ConsumerNavGroup.LIBRARY) {
                DrawerActionItem(
                    label = "Models",
                    description = "Chat models and downloads",
                    icon = RACIcons.Outline.Cpu,
                    onClick = {
                        onDismiss()
                        onModels()
                    },
                )
                DrawerActionItem(
                    label = "Adapters",
                    description = "LoRA personalization",
                    icon = RACIcons.Outline.Adjustments,
                    onClick = {
                        onDismiss()
                        onAdapters()
                    },
                )
            }
            if (group != ConsumerNavGroup.entries.last()) {
                Spacer(Modifier.height(dimens.spacingSm))
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f),
                    modifier = Modifier.padding(horizontal = dimens.spacingLg),
                )
                Spacer(Modifier.height(dimens.spacingSm))
            }
        }
    }
}

@Composable
private fun DrawerHeader() {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingSm),
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = RACIcons.Filled.Bolt,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(dimens.iconLg),
        )
        Column {
            Text(
                text = "RunAnywhere",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "Private AI on this device",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun DrawerSectionLabel(text: String) {
    val dimens = LocalDimens.current
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = dimens.spacingLg, vertical = dimens.spacingXs),
    )
}

@Composable
private fun DrawerRouteItem(
    label: String,
    description: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
) {
    NavigationDrawerItem(
        selected = selected,
        onClick = onClick,
        icon = { Icon(icon, contentDescription = null) },
        label = {
            Column {
                Text(label, style = MaterialTheme.typography.bodyLarge)
                Text(
                    description,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding),
    )
}

@Composable
private fun DrawerActionItem(
    label: String,
    description: String,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    NavigationDrawerItem(
        selected = false,
        onClick = onClick,
        icon = { Icon(icon, contentDescription = null) },
        label = {
            Column {
                Text(label, style = MaterialTheme.typography.bodyLarge)
                Text(
                    description,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding),
    )
}
