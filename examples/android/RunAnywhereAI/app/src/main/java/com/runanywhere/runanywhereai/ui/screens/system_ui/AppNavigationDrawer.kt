package com.runanywhere.runanywhereai.ui.screens.system_ui

import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.navigation.NavDestination
import com.runanywhere.runanywhereai.ui.navigation.Settings
import com.runanywhere.runanywhereai.ui.navigation.isSelected
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

@Composable
fun AppNavigationDrawer(
    destination: NavDestination?,
    onNewChat: () -> Unit,
    onHistory: () -> Unit,
    onSettings: () -> Unit,
    onDismiss: (afterClose: () -> Unit) -> Unit = { afterClose -> afterClose() },
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
            DrawerContent(
                destination = destination,
                onNewChat = onNewChat,
                onHistory = onHistory,
                onSettings = onSettings,
                onDismiss = onDismiss,
            )
        }
    } else {
        ModalDrawerSheet(
            modifier = modifier,
            drawerContainerColor = MaterialTheme.colorScheme.surfaceContainer,
        ) {
            DrawerContent(
                destination = destination,
                onNewChat = onNewChat,
                onHistory = onHistory,
                onSettings = onSettings,
                onDismiss = onDismiss,
            )
        }
    }
}

@Composable
private fun DrawerContent(
    destination: NavDestination?,
    onNewChat: () -> Unit,
    onHistory: () -> Unit,
    onSettings: () -> Unit,
    onDismiss: (afterClose: () -> Unit) -> Unit,
) {
    val dimens = LocalDimens.current
    Column(
        modifier = Modifier
            .fillMaxHeight()
            .verticalScroll(rememberScrollState())
            .padding(vertical = dimens.spacingLg),
    ) {
        DrawerHeader()
        Spacer(Modifier.height(dimens.spacingMd))

        DrawerActionItem(
            label = "New chat",
            description = "Start a clean conversation",
            icon = RACIcons.Outline.Plus,
            onClick = {
                onDismiss(onNewChat)
            },
        )
        DrawerActionItem(
            label = "Search chats",
            description = "All saved conversations",
            icon = RACIcons.Outline.Search,
            onClick = {
                onDismiss(onHistory)
            },
        )
        Spacer(Modifier.height(dimens.spacingSm))
        DrawerActionItem(
            label = "Settings",
            description = "Models, tools, privacy, and downloads",
            icon = if (destination.isSelected(Settings)) RACIcons.Filled.Settings else RACIcons.Outline.Settings,
            selected = destination.isSelected(Settings),
            onClick = {
                onDismiss(onSettings)
            },
        )
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
private fun DrawerActionItem(
    label: String,
    description: String,
    icon: ImageVector,
    selected: Boolean = false,
    onClick: () -> Unit,
) {
    NavigationDrawerItem(
        selected = selected,
        onClick = onClick,
        icon = { Icon(icon, contentDescription = null) },
        label = {
            Column {
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = description,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        },
        modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding),
    )
}
