package com.runanywhere.runanywhereai.ui.screens.chat

import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import com.runanywhere.runanywhereai.data.conversation.ConversationRepository
import com.runanywhere.runanywhereai.data.conversation.ConversationSummary
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationHistorySheet(
    onSelect: (String) -> Unit,
    onDelete: (String) -> Unit,
    onRename: (String, String) -> Unit,
    onTogglePin: (String, Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    val dimens = LocalDimens.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val conversations = ConversationRepository.summaries
    var query by rememberSaveable { mutableStateOf("") }
    var renaming by remember { mutableStateOf<ConversationSummary?>(null) }
    var deleting by remember { mutableStateOf<ConversationSummary?>(null) }

    LaunchedEffect(Unit) { ConversationRepository.refresh() }

    // Mirrors iOS ConversationStore.searchConversations: matches conversation
    // titles and full message text, not just the stored preview snippet.
    val filtered = ConversationRepository.search(query)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        // `fillMaxHeight` on the sheet body is what makes the list usable: a
        // ModalBottomSheet wraps its content, and an unbounded LazyColumn inside a
        // wrapping Column measures to a single row — the sheet then opened one item
        // tall no matter how much history existed. Weighting the list also keeps the
        // title and search field pinned while the rows scroll under them.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingSm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "History",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                // A count is the cheapest way to tell "nothing saved" apart from
                // "the list failed to render" — the exact ambiguity of a one-row sheet.
                if (conversations.isNotEmpty()) {
                    Text(
                        text = if (query.isBlank()) {
                            "${conversations.size} saved"
                        } else {
                            "${filtered.size} of ${conversations.size}"
                        },
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (conversations.isNotEmpty()) {
                SearchField(
                    query = query,
                    onQueryChange = { query = it },
                    modifier = Modifier.padding(horizontal = dimens.spacingLg),
                )
            }

            when {
                conversations.isEmpty() -> HistoryEmptyState(
                    title = "No conversations yet",
                    body = "Chats are saved here automatically as soon as you send your first message.",
                    icon = RACIcons.Outline.MessageCircle,
                    modifier = Modifier.weight(1f),
                )
                filtered.isEmpty() -> HistoryEmptyState(
                    title = "No matches for “$query”",
                    body = "Search looks at conversation titles and every message inside them.",
                    icon = RACIcons.Outline.Search,
                    action = "Clear search" to { query = "" },
                    modifier = Modifier.weight(1f),
                )
                else -> LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(bottom = dimens.spacingXl),
                ) {
                    items(filtered, key = { it.id }) { conversation ->
                        ConversationRow(
                            conversation = conversation,
                            onClick = { onSelect(conversation.id) },
                            onRename = { renaming = conversation },
                            onTogglePin = { onTogglePin(conversation.id, !conversation.pinned) },
                            onDelete = { deleting = conversation },
                            modifier = Modifier.animateItem(
                                fadeInSpec = AppMotion.standard(),
                                placementSpec = AppMotion.springDefault(),
                                fadeOutSpec = AppMotion.exit(),
                            ),
                        )
                    }
                }
            }
        }
    }

    renaming?.let { target ->
        RenameDialog(
            initialTitle = target.title,
            onConfirm = {
                onRename(target.id, it)
                renaming = null
            },
            onDismiss = { renaming = null },
        )
    }

    deleting?.let { target ->
        DeleteDialog(
            title = target.title,
            onConfirm = {
                onDelete(target.id)
                deleting = null
            },
            onDismiss = { deleting = null },
        )
    }
}

@Composable
private fun SearchField(query: String, onQueryChange: (String) -> Unit, modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(dimens.radiusFull),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Icon(
                imageVector = RACIcons.Outline.Search,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconSm),
            )
            Box(modifier = Modifier.weight(1f)) {
                if (query.isEmpty()) {
                    Text(
                        text = "Search",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    )
                }
                BasicTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                )
            }
        }
    }
}

@Composable
private fun ConversationRow(
    conversation: ConversationSummary,
    onClick: () -> Unit,
    onRename: () -> Unit,
    onTogglePin: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    var menuOpen by remember { mutableStateOf(false) }

    Surface(color = MaterialTheme.colorScheme.surfaceContainer, modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = if (conversation.pinned) RACIcons.Outline.Pin else RACIcons.Outline.MessageCircle,
                contentDescription = null,
                tint = if (conversation.pinned) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconMd),
            )

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = conversation.title,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                // Context around the matched message text, shown only while
                // searching (mirrors iOS ConversationRow's matching preview).
                conversation.matchPreview?.let { preview ->
                    Text(
                        text = preview,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Text(
                    text = relativeTime(conversation.updatedAt),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Box {
                IconButton(onClick = { menuOpen = true }) {
                    Icon(
                        imageVector = RACIcons.Outline.DotsVertical,
                        contentDescription = "More options for ${conversation.title}",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(dimens.iconSm),
                    )
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text("Rename") },
                        leadingIcon = { Icon(RACIcons.Outline.Pencil, null, Modifier.size(dimens.iconSm)) },
                        onClick = { menuOpen = false; onRename() },
                    )
                    DropdownMenuItem(
                        text = { Text(if (conversation.pinned) "Unpin" else "Pin") },
                        leadingIcon = { Icon(RACIcons.Outline.Pin, null, Modifier.size(dimens.iconSm)) },
                        onClick = { menuOpen = false; onTogglePin() },
                    )
                    DropdownMenuItem(
                        text = { Text("Delete") },
                        leadingIcon = { Icon(RACIcons.Outline.Trash, null, Modifier.size(dimens.iconSm)) },
                        onClick = { menuOpen = false; onDelete() },
                    )
                }
            }
        }
    }
}

@Composable
private fun DeleteDialog(title: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Delete conversation?") },
        text = { Text("Delete \"$title\" from this device? This cannot be undone.") },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text("Delete", color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun RenameDialog(initialTitle: String, onConfirm: (String) -> Unit, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf(initialTitle) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rename conversation") },
        text = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(name) }, enabled = name.isNotBlank()) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/**
 * An empty sheet has to explain itself. The old one-liner ("No conversations yet")
 * left the reader guessing whether history was empty or broken, and offered nothing
 * to do about it — so each state now carries a reason and, where one exists, the
 * single action that resolves it.
 */
@Composable
private fun HistoryEmptyState(
    title: String,
    body: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    action: Pair<String, () -> Unit>? = null,
) {
    val dimens = LocalDimens.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = dimens.spacingXl, vertical = dimens.spacingXl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd, Alignment.CenterVertically),
    ) {
        Box(
            modifier = Modifier
                .size(dimens.artCircle)
                .clip(RoundedCornerShape(dimens.radiusFull))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconLg),
            )
        }
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            textAlign = TextAlign.Center,
        )
        Text(
            text = body,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        action?.let { (label, onClick) ->
            TextButton(onClick = onClick) { Text(label) }
        }
    }
}

private fun relativeTime(timestamp: Long): String =
    DateUtils.getRelativeTimeSpanString(
        timestamp,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
    ).toString()
