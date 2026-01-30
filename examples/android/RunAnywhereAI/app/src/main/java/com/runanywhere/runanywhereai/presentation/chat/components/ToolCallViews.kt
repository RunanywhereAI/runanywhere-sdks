package com.runanywhere.runanywhereai.presentation.chat.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.domain.models.ToolCallInfo
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppTypography

/**
 * Tool call indicator button - matches iOS ToolCallIndicator
 * Shows a small chip with the tool name that can be tapped to see details
 */
@Composable
fun ToolCallIndicator(
    toolCallInfo: ToolCallInfo,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val backgroundColor = if (toolCallInfo.success) {
        AppColors.primaryAccent.copy(alpha = 0.1f)
    } else {
        AppColors.primaryOrange.copy(alpha = 0.1f)
    }
    
    val borderColor = if (toolCallInfo.success) {
        AppColors.primaryAccent.copy(alpha = 0.3f)
    } else {
        AppColors.primaryOrange.copy(alpha = 0.3f)
    }
    
    val iconTint = if (toolCallInfo.success) {
        AppColors.primaryAccent
    } else {
        AppColors.primaryOrange
    }

    Surface(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable { onTap() },
        color = backgroundColor,
        shape = RoundedCornerShape(8.dp),
    ) {
        Row(
            modifier = Modifier
                .border(0.5.dp, borderColor, RoundedCornerShape(8.dp))
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                imageVector = if (toolCallInfo.success) Icons.Default.Build else Icons.Default.Warning,
                contentDescription = null,
                modifier = Modifier.size(12.dp),
                tint = iconTint,
            )
            Text(
                text = toolCallInfo.toolName,
                style = AppTypography.caption2,
                color = AppColors.textSecondary,
                maxLines = 1,
            )
        }
    }
}

/**
 * Tool call detail sheet - matches iOS ToolCallDetailSheet
 * Shows full details of a tool call including arguments and results as JSON
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ToolCallDetailSheet(
    toolCallInfo: ToolCallInfo,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // Header
            Text(
                text = "Tool Call",
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            
            // Status section
            StatusSection(success = toolCallInfo.success)
            
            // Tool name section
            DetailSection(title = "Tool", content = toolCallInfo.toolName)
            
            // Arguments section
            CodeSection(title = "Arguments", code = toolCallInfo.arguments)
            
            // Result section (if available)
            toolCallInfo.result?.let { result ->
                CodeSection(title = "Result", code = result)
            }
            
            // Error section (if available)
            toolCallInfo.error?.let { error ->
                DetailSection(title = "Error", content = error, isError = true)
            }
            
            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun StatusSection(success: Boolean) {
    val backgroundColor = if (success) {
        AppColors.statusGreen.copy(alpha = 0.1f)
    } else {
        AppColors.primaryRed.copy(alpha = 0.1f)
    }
    
    val iconTint = if (success) AppColors.statusGreen else AppColors.primaryRed
    
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(backgroundColor, RoundedCornerShape(12.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            imageVector = if (success) Icons.Default.CheckCircle else Icons.Default.Cancel,
            contentDescription = null,
            modifier = Modifier.size(24.dp),
            tint = iconTint,
        )
        Text(
            text = if (success) "Success" else "Failed",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun DetailSection(
    title: String,
    content: String,
    isError: Boolean = false,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title,
            style = AppTypography.caption,
            color = AppColors.textSecondary,
        )
        Text(
            text = content,
            style = MaterialTheme.typography.bodyMedium,
            color = if (isError) AppColors.primaryRed else MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun CodeSection(
    title: String,
    code: String,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title,
            style = AppTypography.caption,
            color = AppColors.textSecondary,
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    MaterialTheme.colorScheme.surfaceVariant,
                    RoundedCornerShape(8.dp)
                )
                .padding(12.dp)
                .horizontalScroll(rememberScrollState())
        ) {
            Text(
                text = code,
                style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Tool calling active indicator - matches iOS ToolCallingActiveIndicator
 * Shows animated indicator when tool is being called
 */
@Composable
fun ToolCallingActiveIndicator(
    modifier: Modifier = Modifier,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "rotation")
    val rotation by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "rotation"
    )
    
    Row(
        modifier = modifier
            .background(
                AppColors.primaryAccent.copy(alpha = 0.1f),
                RoundedCornerShape(8.dp)
            )
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Settings,
            contentDescription = null,
            modifier = Modifier
                .size(12.dp)
                .graphicsLayer { rotationZ = rotation },
            tint = AppColors.primaryAccent,
        )
        Text(
            text = "Calling tool...",
            style = AppTypography.caption2,
            color = AppColors.textSecondary,
        )
    }
}
