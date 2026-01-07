package com.runanywhere.runanywhereai.presentation.chat.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp

/**
 * Message input component for typing and sending messages
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessageInput(
    text: String,
    onTextChange: (String) -> Unit,
    onSendMessage: () -> Unit,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier,
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            OutlinedTextField(
                value = text,
                onValueChange = onTextChange,
                modifier = Modifier.weight(1f),
                placeholder = {
                    Text("Type a message...")
                },
                enabled = enabled,
                maxLines = 4,
                keyboardOptions =
                    KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                        imeAction = ImeAction.Send,
                    ),
                keyboardActions =
                    KeyboardActions(
                        onSend = {
                            if (text.isNotBlank() && enabled) {
                                onSendMessage()
                            }
                        },
                    ),
            )

            Spacer(modifier = Modifier.width(8.dp))

            FilledIconButton(
                onClick = onSendMessage,
                enabled = enabled && text.isNotBlank(),
            ) {
                Icon(
                    Icons.Default.Send,
                    contentDescription = "Send message",
                )
            }
        }
    }
}
