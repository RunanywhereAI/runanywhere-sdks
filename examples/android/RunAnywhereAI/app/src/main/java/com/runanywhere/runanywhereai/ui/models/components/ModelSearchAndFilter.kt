package com.runanywhere.runanywhereai.ui.models.components

import androidx.compose.animation.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.GetApp
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Close as FilterListOff
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.data.repository.ModelInfo
import com.runanywhere.runanywhereai.llm.LLMFramework

/**
 * Model search and filtering component
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelSearchAndFilter(
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    selectedFrameworks: Set<LLMFramework>,
    onFrameworkToggle: (LLMFramework) -> Unit,
    selectedSizeRange: SizeRange,
    onSizeRangeChange: (SizeRange) -> Unit,
    showOnlyDownloaded: Boolean,
    onShowOnlyDownloadedChange: (Boolean) -> Unit,
    sortBy: ModelSortBy,
    onSortByChange: (ModelSortBy) -> Unit,
    isFilterExpanded: Boolean,
    onToggleFilterExpanded: () -> Unit,
    modifier: Modifier = Modifier
) {
    val keyboardController = LocalSoftwareKeyboardController.current

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Search bar
        OutlinedTextField(
            value = searchQuery,
            onValueChange = onSearchQueryChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Search models...") },
            leadingIcon = {
                Icon(
                    imageVector = Icons.Filled.Search,
                    contentDescription = "Search"
                )
            },
            trailingIcon = {
                Row {
                    if (searchQuery.isNotEmpty()) {
                        IconButton(
                            onClick = { onSearchQueryChange("") }
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Clear,
                                contentDescription = "Clear search"
                            )
                        }
                    }

                    IconButton(
                        onClick = onToggleFilterExpanded
                    ) {
                        Icon(
                            imageVector = if (isFilterExpanded) {
                                Icons.Filled.FilterListOff
                            } else {
                                Icons.Filled.FilterList
                            },
                            contentDescription = if (isFilterExpanded) {
                                "Hide filters"
                            } else {
                                "Show filters"
                            }
                        )
                    }
                }
            },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Text,
                imeAction = ImeAction.Search
            ),
            keyboardActions = KeyboardActions(
                onSearch = { keyboardController?.hide() }
            ),
            singleLine = true,
            shape = RoundedCornerShape(12.dp)
        )

        // Filter section
        AnimatedVisibility(
            visible = isFilterExpanded,
            enter = expandVertically() + fadeIn(),
            exit = shrinkVertically() + fadeOut()
        ) {
            FilterSection(
                selectedFrameworks = selectedFrameworks,
                onFrameworkToggle = onFrameworkToggle,
                selectedSizeRange = selectedSizeRange,
                onSizeRangeChange = onSizeRangeChange,
                showOnlyDownloaded = showOnlyDownloaded,
                onShowOnlyDownloadedChange = onShowOnlyDownloadedChange,
                sortBy = sortBy,
                onSortByChange = onSortByChange
            )
        }

        // Active filters summary
        if (selectedFrameworks.isNotEmpty() || selectedSizeRange != SizeRange.ALL || showOnlyDownloaded) {
            ActiveFiltersSummary(
                selectedFrameworks = selectedFrameworks,
                onFrameworkToggle = onFrameworkToggle,
                selectedSizeRange = selectedSizeRange,
                onSizeRangeChange = onSizeRangeChange,
                showOnlyDownloaded = showOnlyDownloaded,
                onShowOnlyDownloadedChange = onShowOnlyDownloadedChange
            )
        }
    }
}

/**
 * Filter section with all filter options
 */
@Composable
private fun FilterSection(
    selectedFrameworks: Set<LLMFramework>,
    onFrameworkToggle: (LLMFramework) -> Unit,
    selectedSizeRange: SizeRange,
    onSizeRangeChange: (SizeRange) -> Unit,
    showOnlyDownloaded: Boolean,
    onShowOnlyDownloadedChange: (Boolean) -> Unit,
    sortBy: ModelSortBy,
    onSortByChange: (ModelSortBy) -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Framework filter
            FilterGroup(
                title = "Frameworks",
                icon = Icons.Filled.Build
            ) {
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(LLMFramework.values()) { framework ->
                        FrameworkFilterChip(
                            framework = framework,
                            isSelected = framework in selectedFrameworks,
                            onToggle = { onFrameworkToggle(framework) }
                        )
                    }
                }
            }

            // Size filter
            FilterGroup(
                title = "Model Size",
                icon = Icons.Filled.Save
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    SizeRange.values().forEach { range ->
                        SizeFilterChip(
                            sizeRange = range,
                            isSelected = selectedSizeRange == range,
                            onSelect = { onSizeRangeChange(range) }
                        )
                    }
                }
            }

            // Sort and display options
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Sort by dropdown
                SortByDropdown(
                    sortBy = sortBy,
                    onSortByChange = onSortByChange,
                    modifier = Modifier.weight(1f)
                )

                Spacer(modifier = Modifier.width(16.dp))

                // Show only downloaded toggle
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Downloaded only",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Switch(
                        checked = showOnlyDownloaded,
                        onCheckedChange = onShowOnlyDownloadedChange
                    )
                }
            }
        }
    }
}

/**
 * Filter group with title and icon
 */
@Composable
private fun FilterGroup(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(18.dp)
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
        }

        content()
    }
}

/**
 * Framework filter chip
 */
@Composable
private fun FrameworkFilterChip(
    framework: LLMFramework,
    isSelected: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    val (color, displayName) = getFrameworkDisplayInfo(framework)

    FilterChip(
        selected = isSelected,
        onClick = onToggle,
        label = { Text(displayName) },
        modifier = modifier,
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = color.copy(alpha = 0.2f),
            selectedLabelColor = color,
            selectedLeadingIconColor = color
        ),
        border = FilterChipDefaults.filterChipBorder(
            enabled = true,
            selected = isSelected,
            borderColor = if (!isSelected) MaterialTheme.colorScheme.outline else color,
            selectedBorderColor = color
        )
    )
}

/**
 * Size filter chip
 */
@Composable
private fun SizeFilterChip(
    sizeRange: SizeRange,
    isSelected: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier
) {
    FilterChip(
        selected = isSelected,
        onClick = onSelect,
        label = { Text(sizeRange.displayName) },
        modifier = modifier
    )
}

/**
 * Sort by dropdown
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SortByDropdown(
    sortBy: ModelSortBy,
    onSortByChange: (ModelSortBy) -> Unit,
    modifier: Modifier = Modifier
) {
    var expanded by remember { mutableStateOf(false) }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = !expanded },
        modifier = modifier
    ) {
        OutlinedTextField(
            readOnly = true,
            value = sortBy.displayName,
            onValueChange = {},
            label = { Text("Sort by") },
            trailingIcon = {
                ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded)
            },
            modifier = Modifier
                .menuAnchor()
                .fillMaxWidth()
        )

        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            ModelSortBy.values().forEach { option ->
                DropdownMenuItem(
                    text = { Text(option.displayName) },
                    onClick = {
                        onSortByChange(option)
                        expanded = false
                    },
                    leadingIcon = {
                        Icon(
                            imageVector = option.icon,
                            contentDescription = null
                        )
                    }
                )
            }
        }
    }
}

/**
 * Active filters summary
 */
@Composable
private fun ActiveFiltersSummary(
    selectedFrameworks: Set<LLMFramework>,
    onFrameworkToggle: (LLMFramework) -> Unit,
    selectedSizeRange: SizeRange,
    onSizeRangeChange: (SizeRange) -> Unit,
    showOnlyDownloaded: Boolean,
    onShowOnlyDownloadedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Framework filters
        items(selectedFrameworks.toList()) { framework ->
            ActiveFilterChip(
                text = getFrameworkDisplayInfo(framework).second,
                onRemove = { onFrameworkToggle(framework) }
            )
        }

        // Size range filter
        if (selectedSizeRange != SizeRange.ALL) {
            item {
                ActiveFilterChip(
                    text = selectedSizeRange.displayName,
                    onRemove = { onSizeRangeChange(SizeRange.ALL) }
                )
            }
        }

        // Downloaded only filter
        if (showOnlyDownloaded) {
            item {
                ActiveFilterChip(
                    text = "Downloaded only",
                    onRemove = { onShowOnlyDownloadedChange(false) }
                )
            }
        }
    }
}

/**
 * Active filter chip with remove button
 */
@Composable
private fun ActiveFilterChip(
    text: String,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.primaryContainer,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.3f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )

            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "Remove filter",
                modifier = Modifier
                    .size(16.dp)
                    .clickable { onRemove() },
                tint = MaterialTheme.colorScheme.onPrimaryContainer
            )
        }
    }
}

/**
 * Model size ranges
 */
enum class SizeRange(val displayName: String, val minBytes: Long, val maxBytes: Long) {
    ALL("All Sizes", 0L, Long.MAX_VALUE),
    SMALL("< 1GB", 0L, 1024L * 1024 * 1024),
    MEDIUM("1-5GB", 1024L * 1024 * 1024, 5L * 1024 * 1024 * 1024),
    LARGE("5-10GB", 5L * 1024 * 1024 * 1024, 10L * 1024 * 1024 * 1024),
    EXTRA_LARGE("> 10GB", 10L * 1024 * 1024 * 1024, Long.MAX_VALUE)
}

/**
 * Model sorting options
 */
enum class ModelSortBy(val displayName: String, val icon: ImageVector) {
    NAME("Name", Icons.Filled.List),
    SIZE_ASC("Size (Small to Large)", Icons.Filled.KeyboardArrowUp),
    SIZE_DESC("Size (Large to Small)", Icons.Filled.KeyboardArrowDown),
    FRAMEWORK("Framework", Icons.Filled.Build),
    DOWNLOAD_STATUS("Download Status", Icons.Filled.GetApp),
    PERFORMANCE("Performance", Icons.Filled.Timer)
}

/**
 * Extension function to apply filters and sorting to model list
 */
fun List<ModelInfo>.applyFiltersAndSort(
    searchQuery: String,
    selectedFrameworks: Set<LLMFramework>,
    selectedSizeRange: SizeRange,
    showOnlyDownloaded: Boolean,
    sortBy: ModelSortBy
): List<ModelInfo> {
    return this
        .filter { model ->
            // Search query filter
            if (searchQuery.isNotEmpty()) {
                model.name.contains(searchQuery, ignoreCase = true) ||
                model.description.contains(searchQuery, ignoreCase = true) ||
                model.id.contains(searchQuery, ignoreCase = true)
            } else true
        }
        .filter { model ->
            // Framework filter
            selectedFrameworks.isEmpty() || model.framework in selectedFrameworks
        }
        .filter { model ->
            // Size range filter
            model.sizeBytes in selectedSizeRange.minBytes..selectedSizeRange.maxBytes
        }
        .filter { model ->
            // Downloaded only filter
            !showOnlyDownloaded || model.isDownloaded
        }
        .sortedWith { a, b ->
            when (sortBy) {
                ModelSortBy.NAME -> a.name.compareTo(b.name)
                ModelSortBy.SIZE_ASC -> a.sizeBytes.compareTo(b.sizeBytes)
                ModelSortBy.SIZE_DESC -> b.sizeBytes.compareTo(a.sizeBytes)
                ModelSortBy.FRAMEWORK -> a.framework.name.compareTo(b.framework.name)
                ModelSortBy.DOWNLOAD_STATUS -> {
                    when {
                        a.isDownloaded && !b.isDownloaded -> -1
                        !a.isDownloaded && b.isDownloaded -> 1
                        else -> a.name.compareTo(b.name)
                    }
                }
                ModelSortBy.PERFORMANCE -> {
                    // Sort by estimated performance (smaller models are generally faster)
                    a.sizeBytes.compareTo(b.sizeBytes)
                }
            }
        }
}

// Helper function to get framework display information
private fun getFrameworkDisplayInfo(framework: LLMFramework): Pair<Color, String> {
    return when (framework) {
        LLMFramework.GEMINI_NANO -> Color(0xFF4285F4) to "Gemini"
        LLMFramework.TFLITE -> Color(0xFFFF6F00) to "TFLite"
        LLMFramework.LLAMA_CPP -> Color(0xFF8BC34A) to "llama.cpp"
        LLMFramework.ONNX_RUNTIME -> Color(0xFF9C27B0) to "ONNX"
        LLMFramework.EXECUTORCH -> Color(0xFFE91E63) to "ExecuTorch"
        LLMFramework.MLC_LLM -> Color(0xFF00BCD4) to "MLC-LLM"
        LLMFramework.MEDIAPIPE -> Color(0xFF607D8B) to "MediaPipe"
        LLMFramework.PICOLLM -> Color(0xFF795548) to "picoLLM"
        LLMFramework.AI_CORE -> Color(0xFF3F51B5) to "AI Core"
    }
}
