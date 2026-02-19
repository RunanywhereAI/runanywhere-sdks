package com.runanywhere.runanywhereai.presentation.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppColors

/**
 * Bottom nav tabs matching iOS exactly:
 * Chat, Vision, Voice, More, Settings
 *
 * iOS Reference: ContentView.swift TabView
 */
enum class BottomNavTab {
    Chat, Vision, Voice, More, Settings
}

@Composable
fun AppBottomNavigationBar(
    selectedTab: BottomNavTab,
    onTabSelected: (BottomNavTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                elevation = 16.dp,
                shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
                ambientColor = Color.Black.copy(alpha = 0.08f),
                spotColor = Color.Black.copy(alpha = 0.12f),
            ),
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 8.dp)
                .navigationBarsPadding(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BottomNavTab.entries.forEach { tab ->
                BottomNavItem(
                    tab = tab,
                    isSelected = selectedTab == tab,
                    onClick = { onTabSelected(tab) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun BottomNavItem(
    tab: BottomNavTab,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tabColor = getTabAccentColor(tab)

    val iconScale by animateFloatAsState(
        targetValue = if (isSelected) 1.1f else 1.0f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "icon_scale",
    )
    val textColor by animateColorAsState(
        targetValue = if (isSelected) tabColor else MaterialTheme.colorScheme.onSurfaceVariant,
        label = "text_color",
    )
    val iconColor by animateColorAsState(
        targetValue = if (isSelected) tabColor else MaterialTheme.colorScheme.onSurfaceVariant,
        label = "icon_color",
    )

    Column(
        modifier = modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            )
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        // Icon with optional pill background when selected
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(width = 56.dp, height = 32.dp)
                .clip(RoundedCornerShape(16.dp))
                .then(
                    if (isSelected) {
                        Modifier.background(tabColor.copy(alpha = 0.12f))
                    } else {
                        Modifier
                    }
                ),
        ) {
            Icon(
                imageVector = if (isSelected) getTabIconFilled(tab) else getTabIconOutlined(tab),
                contentDescription = tab.name,
                modifier = Modifier
                    .size(22.dp)
                    .scale(iconScale),
                tint = iconColor,
            )
        }

        Spacer(modifier = Modifier.height(2.dp))

        // Label
        Text(
            text = getTabLabel(tab),
            style = if (isSelected) MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold) else MaterialTheme.typography.labelSmall,
            color = textColor,
            maxLines = 1,
        )
    }
}

private fun getTabLabel(tab: BottomNavTab): String {
    return when (tab) {
        BottomNavTab.Chat -> "Chat"
        BottomNavTab.Vision -> "Vision"
        BottomNavTab.Voice -> "Voice"
        BottomNavTab.More -> "More"
        BottomNavTab.Settings -> "Settings"
    }
}

private fun getTabIconFilled(tab: BottomNavTab): ImageVector {
    return when (tab) {
        BottomNavTab.Chat -> Icons.Outlined.ChatBubbleOutline
        BottomNavTab.Vision -> Icons.Filled.Visibility
        BottomNavTab.Voice -> Icons.Filled.Mic
        BottomNavTab.More -> Icons.Filled.MoreHoriz
        BottomNavTab.Settings -> Icons.Filled.Settings
    }
}

private fun getTabIconOutlined(tab: BottomNavTab): ImageVector {
    return when (tab) {
        BottomNavTab.Chat -> Icons.Outlined.ChatBubbleOutline
        BottomNavTab.Vision -> Icons.Outlined.Visibility
        BottomNavTab.Voice -> Icons.Outlined.Mic
        BottomNavTab.More -> Icons.Outlined.MoreHoriz
        BottomNavTab.Settings -> Icons.Outlined.Settings
    }
}

private fun getTabAccentColor(tab: BottomNavTab): Color {
    return when (tab) {
        BottomNavTab.Chat -> AppColors.primaryAccent
        BottomNavTab.Vision -> AppColors.primaryAccent
        BottomNavTab.Voice -> AppColors.primaryAccent
        BottomNavTab.More -> AppColors.primaryAccent
        BottomNavTab.Settings -> AppColors.primaryAccent
    }
}
