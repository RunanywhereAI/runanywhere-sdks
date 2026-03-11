Performance (must-do):
- collectAsStateWithLifecycle() everywhere — not collectAsState
- key + contentType on all LazyColumn items
- @Immutable on data classes passed to composables (ChatMessage, etc.)
- derivedStateOf for computed booleans (e.g. canSend, showButton)
- Defer state reads with lambda modifiers (Modifier.offset {}, drawBehind {})
- kotlinx-collections-immutable for list state (ImmutableList instead of List)

State (must-do):
- Sealed interface for UiState (Loading, Success, Error)
- Channel for one-shot events (navigation, snackbar)
- Never expose Mutable* types from ViewModel
- rememberSaveable for user input that survives config changes

Adaptive (should-do):
- NavigationSuiteScaffold auto-switches bottom bar → rail → drawer based on screen width
- WindowSizeClass for responsive column counts
- ListDetailPaneScaffold for chat on tablets (list + detail side by side)

M3 Expressive (nice-to-have):
- MaterialExpressiveTheme instead of MaterialTheme (dedicated motionScheme)
- New components: ButtonGroup, SplitButtonLayout, LoadingIndicator
- Extended shapes: largeIncreased

Dependencies we need to add:
- lifecycle-runtime-compose (for collectAsStateWithLifecycle)
- kotlinx-collections-immutable (for stable lists)