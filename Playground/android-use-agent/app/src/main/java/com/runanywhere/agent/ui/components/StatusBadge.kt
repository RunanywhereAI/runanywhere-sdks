package com.runanywhere.agent.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.runanywhere.agent.AgentViewModel

@Composable
fun StatusBadge(
    status: AgentViewModel.Status,
    modifier: Modifier = Modifier
) {
    val (color, text) = when (status) {
        AgentViewModel.Status.IDLE -> Pair(Color(0xFF6C757D), "IDLE")
        AgentViewModel.Status.RUNNING -> Pair(Color(0xFF0D6EFD), "RUNNING")
        AgentViewModel.Status.DONE -> Pair(Color(0xFF198754), "DONE")
        AgentViewModel.Status.ERROR -> Pair(Color(0xFFDC3545), "ERROR")
    }

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(color.copy(alpha = 0.15f))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(color)
        )
        Text(
            text = text,
            color = color,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}
