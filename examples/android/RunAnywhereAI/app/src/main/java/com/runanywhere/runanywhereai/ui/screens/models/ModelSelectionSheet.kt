package com.runanywhere.runanywhereai.ui.screens.models

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.runanywhere.runanywhereai.download.ModelDownloadService
import com.runanywhere.runanywhereai.ui.connect.ConnectClientViewModel
import com.runanywhere.runanywhereai.ui.screens.models.huggingface.HuggingFaceSearchSheet
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.connect.ConnectHost
import com.runanywhere.sdk.public.connect.ConnectState
import com.runanywhere.sdk.public.connect.ConnectStatus
import ai.runanywhere.proto.v1.InferenceFramework
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelSelectionSheet(
    viewModel: ModelSelectionViewModel,
    onDismiss: () -> Unit,
    connectController: ConnectClientViewModel? = null,
) {
    val dimens = LocalDimens.current
    val state = viewModel.state
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val device = remember { runCatching { DeviceInfo.current() }.getOrNull() }
    var pendingDelete by remember { mutableStateOf<RAModelInfo?>(null) }
    var showHfSearch by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val connectState by connectController?.state?.collectAsState()
        ?: remember { mutableStateOf(ConnectState()) }
    var localNetworkDenied by remember { mutableStateOf(false) }
    val localNetworkPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        localNetworkDenied = !granted
        if (granted) connectController?.startDiscovery()
    }
    val startConnectDiscovery = {
        localNetworkDenied = false
        if (
            Build.VERSION.SDK_INT >= 37 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_LOCAL_NETWORK) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            localNetworkPermission.launch(Manifest.permission.ACCESS_LOCAL_NETWORK)
        } else {
            connectController?.startDiscovery()
        }
        Unit
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = dimens.radiusLg, topEnd = dimens.radiusLg),
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        dragHandle = null,
        contentWindowInsets = { WindowInsets.systemBars },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = dimens.spacingXl),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Header(title = viewModel.title, onCancel = onDismiss)

            // Models first. Everything that used to sit above them — a local-network
            // host connector, its permission disclaimer, and a Model/Chip/Memory/NPU
            // spec table — put the one model this device had already downloaded four
            // screens below the fold, so opening the picker to switch models began
            // with scrolling past hardware trivia.
            when {
                state.isLoading -> CenterNote("Loading models…", showSpinner = true)
                state.models.isEmpty() -> CenterNote("No models available")
                else -> PickerBody(
                    viewModel, state, device, scope, onDismiss,
                    onSelectLocalModel = { connectController?.disconnect() },
                    onDelete = { pendingDelete = it },
                    onAddFromHuggingFace = { showHfSearch = true },
                )
            }

            // Below the catalog: running a model on another machine is the most
            // advanced thing this sheet offers, and it is the only one that asks for
            // a permission.
            if (viewModel.modality == ModelSelectionContext.LLM && connectController != null) {
                Spacer(Modifier.height(dimens.spacingSm))
                ConnectPickerSection(
                    state = connectState,
                    permissionDenied = localNetworkDenied,
                    onFindHost = startConnectDiscovery,
                    onConnect = { host -> connectController.connect(host, onDismiss) },
                    onUseConnected = onDismiss,
                )
            }

            device?.let {
                Spacer(Modifier.height(dimens.spacingSm))
                DeviceStatusCard(it, Modifier.padding(horizontal = dimens.spacingLg))
            }

            Text(
                "All models run privately on your device.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = dimens.spacingLg),
            )
        }
    }

    state.error?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::clearError,
            confirmButton = { TextButton(onClick = viewModel::clearError) { Text("OK") } },
            title = { Text("Error") },
            text = { Text(message) },
        )
    }

    pendingDelete?.let { model ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.delete(model)
                        pendingDelete = null
                    },
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text("Cancel") }
            },
            title = { Text("Delete model") },
            text = { Text("Delete ${model.name} from this device? You can download it again later.") },
        )
    }

    if (showHfSearch) {
        HuggingFaceSearchSheet(
            onDismiss = { showHfSearch = false },
            onModelAdded = { viewModel.refresh() },
        )
    }
}

@Composable
private fun ConnectPickerSection(
    state: ConnectState,
    permissionDenied: Boolean,
    onFindHost: () -> Unit,
    onConnect: (ConnectHost) -> Unit,
    onUseConnected: () -> Unit,
) {
    val dimens = LocalDimens.current
    SectionLabel("Connect")
    val host = state.availableHosts.firstOrNull()
    val title: String
    val subtitle: String
    val icon = when (state.status) {
        ConnectStatus.CONNECTED -> RACIcons.Outline.Check
        ConnectStatus.DISCONNECTED, ConnectStatus.FAILED -> RACIcons.Outline.Refresh
        else -> RACIcons.Outline.Desktop
    }
    val action: (() -> Unit)?
    val actionLabel: String?

    when (state.status) {
        ConnectStatus.IDLE -> {
            title = "Connect to a Host"
            subtitle = "Use a text model hosted on your local network"
            action = onFindHost
            actionLabel = "Find Host"
        }
        ConnectStatus.DISCOVERING -> if (host == null) {
            title = "Looking for Hosts"
            subtitle = "Searching your local network"
            action = null
            actionLabel = null
        } else {
            title = host.displayName
            subtitle = "Text model available on this host"
            action = { onConnect(host) }
            actionLabel = "Connect"
        }
        ConnectStatus.CONNECTING -> {
            title = "Connecting"
            subtitle = state.connectingHost?.displayName ?: "Checking the selected host"
            action = null
            actionLabel = null
        }
        ConnectStatus.CONNECTED -> {
            title = state.activeHost?.displayName ?: "Connected Host"
            subtitle = state.activeModel?.displayName ?: "Hosted text model"
            action = onUseConnected
            actionLabel = "Use"
        }
        ConnectStatus.DISCONNECTED -> {
            title = "Find a Host again"
            subtitle = state.message ?: "The previous connection ended"
            action = onFindHost
            actionLabel = "Retry"
        }
        ConnectStatus.FAILED -> {
            title = "Try Connect again"
            subtitle = state.message ?: "Could not connect to the selected host"
            action = onFindHost
            actionLabel = "Retry"
        }
    }

    ListItem(
        headlineContent = {
            Text(title, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
        },
        supportingContent = {
            Text(subtitle, maxLines = 2, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
        },
        leadingContent = {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        },
        trailingContent = {
            when {
                state.status == ConnectStatus.DISCOVERING && host == null ||
                    state.status == ConnectStatus.CONNECTING -> CircularProgressIndicator(
                    Modifier.size(22.dp),
                    strokeWidth = 2.dp,
                )
                actionLabel != null -> Text(
                    actionLabel,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        },
        modifier = Modifier
            .padding(horizontal = dimens.spacingLg)
            .then(if (action != null) Modifier.clickable(onClick = action) else Modifier),
    )
    Text(
        if (permissionDenied) {
            "Local Network access was denied. Allow it in Android settings to find a host."
        } else {
            "Local Network access is requested only after you choose to find a host."
        },
        style = MaterialTheme.typography.bodySmall,
        color = if (permissionDenied) {
            MaterialTheme.colorScheme.error
        } else {
            MaterialTheme.colorScheme.onSurfaceVariant
        },
        modifier = Modifier.padding(horizontal = dimens.spacingLg),
    )
}

@Composable
private fun PickerBody(
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    device: DeviceInfo?,
    scope: CoroutineScope,
    onDismiss: () -> Unit,
    onSelectLocalModel: () -> Unit,
    onDelete: (RAModelInfo) -> Unit,
    onAddFromHuggingFace: () -> Unit,
) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    var query by remember { mutableStateOf("") }
    val isSearching = query.isNotBlank()

    // Backend/NPU filter. null = "All". Only meaningful when the picker spans more than
    // one backend (e.g. NPU + Llama.cpp on the same device). Order NPU/QHexRT prominent.
    var selectedBackend by remember { mutableStateOf<InferenceFramework?>(null) }
    val backends = remember(state.models) {
        val order = listOf(
            InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            InferenceFramework.INFERENCE_FRAMEWORK_MLX,
            InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
            InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
            InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
        )
        state.models.map { it.framework }.distinct()
            .sortedBy { fw -> order.indexOf(fw).let { if (it < 0) Int.MAX_VALUE else it } }
    }

    val onSelect: (RAModelInfo) -> Unit = { model ->
        scope.launch {
            if (viewModel.select(model)) {
                onSelectLocalModel()
                onDismiss()
            }
        }
    }

    // The download runs in a `dataSync` foreground service whose progress
    // notification Android 13+ silently suppresses unless POST_NOTIFICATIONS is
    // granted. Request it once, just-in-time, before the first download — but the
    // notification is a nicety, so proceed with the download whether the user
    // grants or denies (no re-prompt loop). On API < 33 `notificationsPermitted`
    // returns true, so we download straight through without ever launching.
    val pendingDownload = remember { mutableStateOf<RAModelInfo?>(null) }
    val notificationPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) {
        // Denied or granted: the notification is optional, so start the download.
        pendingDownload.value?.let { viewModel.download(it) }
        pendingDownload.value = null
    }
    val onDownload: (RAModelInfo) -> Unit = { model ->
        if (ModelDownloadService.notificationsPermitted(context)) {
            viewModel.download(model)
        } else {
            pendingDownload.value = model
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    val tier = device?.tier ?: HardwareTier.MID_RANGE
    val hasNpu = device?.hasNpu ?: false
    val isChat = viewModel.modality == ModelSelectionContext.LLM ||
        viewModel.modality == ModelSelectionContext.RAG_LLM

    // Chat pickers get the rich spread (default + a few LLMs + companions); every other
    // modality gets a single scoped "best for this device" highlight.
    val recommendation = remember(state.models, device) {
        if (isChat) ModelRecommendation.recommend(tier, hasNpu, state.models) else null
    }
    val scopedRecommended = remember(state.models, device) {
        if (isChat) null else ModelRecommendation.recommendedFor(viewModel.modality, tier, hasNpu, state.models)
    }
    // Models already on disk, loaded one first. Nothing else in this sheet is one
    // tap from working, so nothing else earns the top: a reader opening the picker
    // to switch models is choosing among these, and a reader who owns none sees the
    // section vanish rather than an empty shell. Suppressed while searching or
    // filtering, both of which are explicit requests to see something else.
    val readyModels = remember(state.models, state.currentModelId) {
        state.models
            .filter { viewModel.isReady(it) }
            .sortedWith(
                compareByDescending<RAModelInfo> { it.id == state.currentModelId }
                    .thenBy { it.effectiveBytes() },
            )
    }
    val showReadySection = !isSearching && selectedBackend == null && readyModels.isNotEmpty()
    if (showReadySection) {
        SectionLabel(if (readyModels.size == 1) "Ready to use" else "Ready to use · ${readyModels.size}")
        readyModels.forEach { model ->
            PickerModelRow(viewModel, state, model, onSelect, onDownload, onDelete)
        }
        Spacer(Modifier.height(dimens.spacingMd))
    }

    // Everything surfaced above the browse list, so the org cards below don't repeat
    // it. Ready models count only when their section actually rendered.
    val surfacedIds = (recommendation?.allIds ?: setOfNotNull(scopedRecommended?.id)) +
        if (showReadySection) readyModels.map { it.id }.toSet() else emptySet()

    // Recommended section only in the default view — hidden while searching OR when a
    // backend filter is active (the filter is an explicit "show me only this backend").
    // A recommendation the user already owns is dropped: it is one row higher under
    // "Ready to use", where it says something stronger than "recommended".
    if (!isSearching && selectedBackend == null) {
        val readyIds = if (showReadySection) readyModels.map { it.id }.toSet() else emptySet()
        when {
            recommendation != null && recommendation.recommendedLLMs.any { it.id !in readyIds } -> {
                RecommendedSection(
                    recommendation, viewModel, state, onSelect, onDownload, onDelete,
                    excludedIds = readyIds,
                )
                Spacer(Modifier.height(dimens.spacingMd))
            }
            scopedRecommended != null && scopedRecommended.id !in readyIds -> {
                SectionLabel("Recommended for your device")
                PickerModelRow(
                    viewModel, state, scopedRecommended, onSelect, onDownload, onDelete,
                    highlightLabel = "Top pick",
                )
                Spacer(Modifier.height(dimens.spacingMd))
            }
        }
    }

    SectionLabel(if (showReadySection) "Get another model" else "Browse by model")
    SearchField(query = query, onQueryChange = { query = it })
    Spacer(Modifier.height(dimens.spacingXs))

    // Bring-your-own model: search Hugging Face for any GGUF and download it. Below
    // the search field, where someone who did not find what they wanted is looking.
    AddFromHuggingFaceRow(onClick = onAddFromHuggingFace)

    // Backend/NPU filter chips — only when the picker spans more than one backend.
    if (backends.size > 1) {
        BackendFilterRow(
            backends = backends,
            selected = selectedBackend,
            onSelect = { selectedBackend = it },
        )
        Spacer(Modifier.height(dimens.spacingXs))
    }

    // Orgs to show. Apply the backend filter first, then (default view only) hide
    // models already surfaced in the recommended section so the list stays short. Search
    // matches org name + model titles + tags only.
    val filteredModels = selectedBackend?.let { fw -> state.models.filter { it.framework == fw } }
        ?: state.models
    val hideSurfaced = !isSearching && selectedBackend == null
    val orgs = filteredModels
        .filter { !hideSurfaced || it.id !in surfacedIds }
        .toOrgGroups()
        .mapNotNull { group ->
            if (!isSearching) return@mapNotNull group
            val matches = group.matchesQuery(query)
            when {
                group.org.matchesQuery(query) -> group
                matches.isNotEmpty() -> group.copy(models = matches)
                else -> null
            }
        }

    if (orgs.isEmpty()) {
        CenterNote(if (isSearching) "No models match your search" else "No additional models")
        return
    }

    // Orgs with anything ready come first; everything else follows in org order. In the
    // default view every ready model was already pulled up top, so this partition only
    // splits anything while searching or filtering — and the sole remaining group needs
    // no second heading under one that already says what the list is for.
    val (installed, downloadable) = orgs.partition { it.hasReadyVariant }
    val sections = buildList {
        if (installed.isNotEmpty()) add("On this device" to installed)
        if (downloadable.isNotEmpty()) {
            val label = when {
                installed.isNotEmpty() -> "More organisations"
                showReadySection -> null
                else -> "All organisations"
            }
            add(label to downloadable)
        }
    }

    sections.forEachIndexed { index, (label, groups) ->
        if (index > 0) Spacer(modifier = Modifier.height(dimens.spacingSm))
        label?.let { SectionLabel(it) }
        groups.forEach { group ->
            OrgCard(
                group = group,
                viewModel = viewModel,
                state = state,
                onSelect = onSelect,
                onDownload = onDownload,
                onDelete = onDelete,
                modifier = Modifier.padding(horizontal = dimens.spacingLg),
                // Auto-expand when search narrows to one or two orgs.
                initiallyExpanded = isSearching && orgs.size <= 2,
            )
        }
    }
}

@Composable
private fun RecommendedSection(
    recommendation: RecommendedSelection,
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    onSelect: (RAModelInfo) -> Unit,
    onDownload: (RAModelInfo) -> Unit,
    onDelete: (RAModelInfo) -> Unit,
    /**
     * Ids already shown under "Ready to use". Recommending a model the reader has
     * already downloaded says less than the row above it does, so it is dropped.
     */
    excludedIds: Set<String> = emptySet(),
) {
    val dimens = LocalDimens.current
    SectionLabel("Recommended for your device")

    val default = recommendation.defaultModel?.takeIf { it.id !in excludedIds }
    default?.let { model ->
        PickerModelRow(
            viewModel, state, model, onSelect, onDownload, onDelete,
            highlightLabel = "Top pick",
        )
    }
    recommendation.recommendedLLMs
        .filter { it.id != default?.id && it.id !in excludedIds }
        .forEach { model ->
            PickerModelRow(viewModel, state, model, onSelect, onDownload, onDelete)
        }

    val companions = listOfNotNull(
        recommendation.vlm,
        recommendation.asr,
        recommendation.tts,
        recommendation.embedding,
    ).filter { it.id !in excludedIds }
    if (companions.isNotEmpty()) {
        Spacer(Modifier.height(dimens.spacingXs))
        SectionLabel("Also recommended")
        companions.forEach { model ->
            PickerModelRow(viewModel, state, model, onSelect, onDownload, onDelete)
        }
    }
}

@Composable
private fun PickerModelRow(
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    model: RAModelInfo,
    onSelect: (RAModelInfo) -> Unit,
    onDownload: (RAModelInfo) -> Unit,
    onDelete: (RAModelInfo) -> Unit,
    highlightLabel: String? = null,
) {
    val dimens = LocalDimens.current
    ModelRow(
        model = model,
        isCurrent = state.currentModelId == model.id,
        isReady = viewModel.isReady(model),
        isBusy = state.busyModelId == model.id,
        progress = if (state.busyModelId == model.id) state.downloadProgress else null,
        interruption = state.interruptionFor(model.id),
        highlightLabel = highlightLabel,
        onSelect = { onSelect(model) },
        onDownload = { onDownload(model) },
        onCancel = { viewModel.cancelDownload(model.id) },
        onDelete = if (viewModel.isDeletable(model)) ({ onDelete(model) }) else null,
        modifier = Modifier.padding(horizontal = dimens.spacingLg),
    )
}

@Composable
private fun AddFromHuggingFaceRow(onClick: () -> Unit) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = dimens.spacingLg)
            .clickable(onClick = onClick)
            .padding(vertical = dimens.spacingSm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            RACIcons.Brands.HuggingFace,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(dimens.iconLg),
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = dimens.spacingMd),
        ) {
            Text(
                "Add from Hugging Face",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                "Search and download any GGUF model",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            RACIcons.Outline.ChevronRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun SearchField(query: String, onQueryChange: (String) -> Unit) {
    val dimens = LocalDimens.current
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = dimens.spacingLg),
        singleLine = true,
        shape = RoundedCornerShape(dimens.radiusLg),
        leadingIcon = { Icon(RACIcons.Outline.Search, contentDescription = null) },
        trailingIcon = {
            if (query.isNotBlank()) {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(RACIcons.Outline.Close, contentDescription = "Clear search")
                }
            }
        },
        placeholder = { Text("Search models — chat, vision, voice…") },
    )
}

// Horizontally-scrollable single-select backend/NPU filter. A leading "All" chip clears
// the filter; tapping the active chip again also clears it. Backend order is set upstream.
@Composable
private fun BackendFilterRow(
    backends: List<InferenceFramework>,
    selected: InferenceFramework?,
    onSelect: (InferenceFramework?) -> Unit,
) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = dimens.spacingLg),
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        FilterChip(
            selected = selected == null,
            onClick = { onSelect(null) },
            label = { Text("All") },
        )
        backends.forEach { framework ->
            FilterChip(
                selected = selected == framework,
                onClick = { onSelect(if (selected == framework) null else framework) },
                label = { Text(framework.filterLabel()) },
                leadingIcon = {
                    Icon(
                        framework.backendIcon(),
                        contentDescription = null,
                        modifier = Modifier.size(dimens.iconSm),
                    )
                },
            )
        }
    }
}

// Friendly-only search: organisation display name. No quant, backend, or ids.
private fun ModelOrg.matchesQuery(query: String): Boolean {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return true
    return displayName.lowercase().contains(q)
}

// Model-level friendly search: name + clean tags only.
private fun OrgGroup.matchesQuery(query: String): List<RAModelInfo> {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return models
    return models.filter { model ->
        val tags = model.consumerTags().joinToString(" ") { it.label }
        "${model.name} ${model.displayTitle()} ${model.variantFeelLabel()} $tags".lowercase().contains(q)
    }
}

@Composable
private fun Header(title: String, onCancel: () -> Unit) {
    val dimens = LocalDimens.current
    Box(modifier = Modifier
        .fillMaxWidth()
        .padding(vertical = dimens.spacingMd)) {
        TextButton(
            onClick = onCancel,
            modifier = Modifier.align(Alignment.CenterStart),
            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.primary)
        ) {
            Text("Cancel", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            maxLines = 2,
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .padding(start = 96.dp, end = 24.dp),
        )
    }
}

@Composable
private fun SectionLabel(text: String) {
    val dimens = LocalDimens.current
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        fontWeight = FontWeight.Medium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = dimens.spacingLg),
    )
}

@Composable
private fun CenterNote(text: String, showSpinner: Boolean = false) {
    val dimens = LocalDimens.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(dimens.spacingXl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (showSpinner) {
            CircularProgressIndicator()
            Spacer(Modifier.height(dimens.spacingMd))
        }
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
