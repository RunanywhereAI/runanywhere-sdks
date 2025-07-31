# Local LLM Sample App Implementation Guide

## 🎯 Overview

This guide provides a complete implementation blueprint for building sample apps that demonstrate all major local LLM frameworks on both iOS and Android platforms. The apps feature a unified interface for comparing different frameworks, managing models, and benchmarking performance.

## 📱 Sample App Features

### Core Functionality
1. **Multi-Framework Support**: Switch between different LLM frameworks
2. **Model Management**: Download, import, and manage models
3. **Chat Interface**: Interactive chat with streaming responses
4. **Performance Monitoring**: Real-time metrics and benchmarking
5. **Model Comparison**: Side-by-side framework comparison
6. **Settings & Configuration**: Framework-specific settings

## 🏗️ Unified Architecture

### Design Principles
- **Framework Abstraction**: Common interface for all LLM frameworks
- **Modular Design**: Easy to add new frameworks
- **Performance First**: Optimized for mobile constraints
- **User Experience**: Smooth, responsive interface

### Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│                    UI Layer                      │
│  ┌──────────┐ ┌──────────┐ ┌────────────────┐  │
│  │   Chat   │ │  Models  │ │   Benchmark    │  │
│  │  Screen  │ │  Screen  │ │    Screen      │  │
│  └──────────┘ └──────────┘ └────────────────┘  │
└─────────────────────────────────────────────────┘
                         │
┌─────────────────────────────────────────────────┐
│               ViewModel Layer                    │
│  ┌──────────┐ ┌──────────┐ ┌────────────────┐  │
│  │   Chat   │ │  Model   │ │   Benchmark    │  │
│  │ViewModel│ │ Manager  │ │   ViewModel    │  │
│  └──────────┘ └──────────┘ └────────────────┘  │
└─────────────────────────────────────────────────┘
                         │
┌─────────────────────────────────────────────────┐
│                Service Layer                     │
│  ┌────────────────────────────────────────────┐ │
│  │          Unified LLM Manager                │ │
│  └────────────────────────────────────────────┘ │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ │
│  │Gemini│ │ ONNX │ │ MLC  │ │TFLite│ │LLama │ │
│  │ Nano │ │  RT  │ │ LLM  │ │      │ │ cpp  │ │
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ │
└─────────────────────────────────────────────────┘
```

## 📱 iOS Implementation

### Project Structure

```
LocalLLMiOS/
├── LocalLLMApp.swift
├── ContentView.swift
├── Features/
│   ├── Chat/
│   │   ├── ChatView.swift
│   │   ├── ChatViewModel.swift
│   │   ├── MessageBubble.swift
│   │   └── TypingIndicator.swift
│   ├── Models/
│   │   ├── ModelListView.swift
│   │   ├── ModelDetailView.swift
│   │   ├── ModelDownloader.swift
│   │   └── ModelManager.swift
│   ├── Benchmark/
│   │   ├── BenchmarkView.swift
│   │   ├── BenchmarkRunner.swift
│   │   └── MetricsView.swift
│   └── Settings/
│       ├── SettingsView.swift
│       └── FrameworkSettings.swift
├── Core/
│   ├── LLM/
│   │   ├── LLMProtocol.swift
│   │   ├── UnifiedLLMService.swift
│   │   └── Frameworks/
│   │       ├── FoundationModelsService.swift
│   │       ├── CoreMLService.swift
│   │       ├── MLXService.swift
│   │       ├── MLCService.swift
│   │       ├── ONNXService.swift
│   │       ├── ExecuTorchService.swift
│   │       ├── LlamaCppService.swift
│   │       └── TFLiteService.swift
│   ├── Models/
│   │   ├── ChatMessage.swift
│   │   ├── ModelInfo.swift
│   │   └── BenchmarkResult.swift
│   └── Utils/
│       ├── PerformanceMonitor.swift
│       ├── MemoryManager.swift
│       └── Extensions.swift
└── Resources/
    ├── Models/
    └── Assets.xcassets
```

### SwiftUI Implementation

```swift
// Main App
@main
struct LocalLLMApp: App {
    @StateObject private var llmManager = UnifiedLLMService()
    @StateObject private var modelManager = ModelManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(llmManager)
                .environmentObject(modelManager)
        }
    }
}

// Content View with Tab Navigation
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
                .tag(0)

            ModelListView()
                .tabItem {
                    Label("Models", systemImage: "square.stack.3d.up")
                }
                .tag(1)

            BenchmarkView()
                .tabItem {
                    Label("Benchmark", systemImage: "speedometer")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
    }
}

// Chat View Implementation
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var llmManager: UnifiedLLMService
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Framework selector
                FrameworkSelector(
                    selectedFramework: $viewModel.selectedFramework
                )
                .padding(.horizontal)

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isGenerating {
                                TypingIndicator()
                                    .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation {
                            proxy.scrollTo(
                                viewModel.isGenerating ? "typing" : viewModel.messages.last?.id,
                                anchor: .bottom
                            )
                        }
                    }
                }

                // Input bar
                HStack(spacing: 12) {
                    TextField("Type a message...", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .disabled(inputText.isEmpty || viewModel.isGenerating)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Local LLM Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Button(model.name) {
                                viewModel.selectModel(model)
                            }
                        }
                    } label: {
                        Label(viewModel.currentModel?.name ?? "Select Model",
                              systemImage: "cpu")
                    }
                }
            }
        }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        Task {
            await viewModel.sendMessage(inputText)
            inputText = ""
        }
    }
}

// Message Bubble Component
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user ? Color.blue : Color(.secondarySystemBackground))
                    )
                    .foregroundColor(message.role == .user ? .white : .primary)

                HStack(spacing: 8) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let metrics = message.metrics {
                        Text("(\(Int(metrics.tokensPerSecond)) tok/s)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75,
                   alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer() }
        }
    }
}

// Model List View
struct ModelListView: View {
    @EnvironmentObject var modelManager: ModelManager
    @State private var showingDownloader = false

    var body: some View {
        NavigationView {
            List {
                Section("Downloaded Models") {
                    ForEach(modelManager.downloadedModels) { model in
                        ModelRow(model: model)
                    }
                }

                Section("Available Models") {
                    ForEach(modelManager.availableModels) { model in
                        ModelDownloadRow(model: model)
                    }
                }
            }
            .navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") {
                        showingDownloader = true
                    }
                }
            }
            .sheet(isPresented: $showingDownloader) {
                ModelImportView()
            }
        }
    }
}

// Benchmark View
struct BenchmarkView: View {
    @StateObject private var benchmarkRunner = BenchmarkRunner()
    @State private var selectedFrameworks: Set<LLMFramework> = []
    @State private var selectedModel: ModelInfo?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Framework selection
                    FrameworkSelectionCard(
                        selectedFrameworks: $selectedFrameworks
                    )

                    // Model selection
                    ModelSelectionCard(
                        selectedModel: $selectedModel
                    )

                    // Run benchmark button
                    Button(action: runBenchmark) {
                        Label("Run Benchmark", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(selectedFrameworks.isEmpty || selectedModel == nil)
                    .padding(.horizontal)

                    // Results
                    if !benchmarkRunner.results.isEmpty {
                        BenchmarkResultsView(results: benchmarkRunner.results)
                    }
                }
            }
            .navigationTitle("Benchmark")
        }
    }

    private func runBenchmark() {
        Task {
            await benchmarkRunner.runBenchmark(
                frameworks: Array(selectedFrameworks),
                model: selectedModel!
            )
        }
    }
}
```

### Core Services Implementation

```swift
// Unified LLM Service
class UnifiedLLMService: ObservableObject {
    @Published var currentFramework: LLMFramework?
    @Published var isInitialized = false

    private var services: [LLMFramework: LLMService] = [:]
    private var currentService: LLMService?

    init() {
        registerAllServices()
    }

    private func registerAllServices() {
        // Register all available frameworks
        if #available(iOS 18.0, *) {
            services[.foundationModels] = FoundationModelsService()
        }
        services[.coreML] = CoreMLService()
        services[.mlx] = MLXService()
        services[.mlc] = MLCService()
        services[.onnx] = ONNXService()
        services[.execuTorch] = ExecuTorchService()
        services[.llamaCpp] = LlamaCppService()
        services[.tfLite] = TFLiteService()
    }

    func selectFramework(_ framework: LLMFramework, modelPath: String) async throws {
        // Clean up previous service
        currentService?.cleanup()

        guard let service = services[framework] else {
            throw LLMError.frameworkNotSupported
        }

        currentService = service
        currentFramework = framework

        try await service.initialize(modelPath: modelPath)
        isInitialized = true
    }

    func generate(prompt: String, options: GenerationOptions) async throws -> String {
        guard let service = currentService, isInitialized else {
            throw LLMError.notInitialized
        }

        return try await service.generate(prompt: prompt, options: options)
    }

    func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let service = currentService, isInitialized else {
            throw LLMError.notInitialized
        }

        try await service.streamGenerate(
            prompt: prompt,
            options: options,
            onToken: onToken
        )
    }
}

// Chat ViewModel
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var selectedFramework: LLMFramework = .mlc
    @Published var currentModel: ModelInfo?
    @Published var availableModels: [ModelInfo] = []

    private let llmService: UnifiedLLMService
    private let performanceMonitor = PerformanceMonitor()

    init(llmService: UnifiedLLMService = UnifiedLLMService()) {
        self.llmService = llmService
        loadAvailableModels()
    }

    func sendMessage(_ content: String) async {
        // Add user message
        let userMessage = ChatMessage(
            role: .user,
            content: content,
            timestamp: Date()
        )
        messages.append(userMessage)

        // Start generating
        isGenerating = true
        performanceMonitor.startMeasurement()

        // Add placeholder assistant message
        var assistantMessage = ChatMessage(
            role: .assistant,
            content: "",
            timestamp: Date()
        )
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1

        do {
            // Stream generation
            try await llmService.streamGenerate(
                prompt: content,
                options: GenerationOptions()
            ) { token in
                Task { @MainActor in
                    self.messages[messageIndex].content += token
                    self.performanceMonitor.recordToken()
                }
            }

            // Update with metrics
            let metrics = performanceMonitor.endMeasurement()
            messages[messageIndex].metrics = metrics

        } catch {
            messages[messageIndex].content = "Error: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    func selectModel(_ model: ModelInfo) {
        currentModel = model
        Task {
            do {
                try await llmService.selectFramework(
                    selectedFramework,
                    modelPath: model.path
                )
            } catch {
                // Handle error
                print("Failed to load model: \(error)")
            }
        }
    }
}

// Model Manager
class ModelManager: ObservableObject {
    @Published var downloadedModels: [ModelInfo] = []
    @Published var availableModels: [ModelInfo] = []
    @Published var downloadProgress: [String: Float] = [:]

    private let documentsPath = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first!.appendingPathComponent("Models")

    init() {
        createModelsDirectory()
        loadDownloadedModels()
        loadAvailableModels()
    }

    func downloadModel(_ model: ModelInfo) async throws {
        let downloader = ModelDownloader()

        for try await progress in downloader.download(
            url: model.downloadURL,
            to: documentsPath.appendingPathComponent(model.filename)
        ) {
            await MainActor.run {
                downloadProgress[model.id] = progress
            }
        }

        await MainActor.run {
            downloadedModels.append(model)
            downloadProgress.removeValue(forKey: model.id)
        }
    }

    private func loadAvailableModels() {
        // Load from remote catalog or bundled list
        availableModels = [
            ModelInfo(
                id: "llama-3.2-3b",
                name: "Llama 3.2 3B",
                size: "1.7GB",
                framework: .execuTorch,
                quantization: "Q4_K_M",
                downloadURL: URL(string: "https://example.com/models/llama-3.2-3b.pte")!
            ),
            ModelInfo(
                id: "phi-3-mini",
                name: "Phi-3 Mini",
                size: "1.5GB",
                framework: .onnx,
                quantization: "INT4",
                downloadURL: URL(string: "https://example.com/models/phi-3-mini.onnx")!
            ),
            // Add more models...
        ]
    }
}
```

## 🤖 Android Implementation

### Project Structure

```
LocalLLMAndroid/
├── app/
│   ├── src/main/java/com/example/localllm/
│   │   ├── MainActivity.kt
│   │   ├── LocalLLMApplication.kt
│   │   ├── ui/
│   │   │   ├── theme/
│   │   │   ├── chat/
│   │   │   │   ├── ChatScreen.kt
│   │   │   │   ├── ChatViewModel.kt
│   │   │   │   └── components/
│   │   │   ├── models/
│   │   │   │   ├── ModelListScreen.kt
│   │   │   │   ├── ModelDetailScreen.kt
│   │   │   │   └── ModelViewModel.kt
│   │   │   ├── benchmark/
│   │   │   │   ├── BenchmarkScreen.kt
│   │   │   │   └── BenchmarkViewModel.kt
│   │   │   └── settings/
│   │   │       └── SettingsScreen.kt
│   │   ├── core/
│   │   │   ├── llm/
│   │   │   │   ├── LLMService.kt
│   │   │   │   ├── UnifiedLLMManager.kt
│   │   │   │   └── frameworks/
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   ├── repository/
│   │   │   │   └── database/
│   │   │   └── utils/
│   │   └── di/
│   │       └── AppModule.kt
│   └── build.gradle.kts
└── build.gradle.kts
```

### Jetpack Compose Implementation

```kotlin
// Main Activity
@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            LocalLLMTheme {
                LocalLLMApp()
            }
        }
    }
}

// Main App Composable
@Composable
fun LocalLLMApp() {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            BottomNavigation(navController)
        }
    ) { paddingValues ->
        NavHost(
            navController = navController,
            startDestination = Screen.Chat.route,
            modifier = Modifier.padding(paddingValues)
        ) {
            composable(Screen.Chat.route) {
                ChatScreen()
            }
            composable(Screen.Models.route) {
                ModelListScreen()
            }
            composable(Screen.Benchmark.route) {
                BenchmarkScreen()
            }
            composable(Screen.Settings.route) {
                SettingsScreen()
            }
        }
    }
}

// Bottom Navigation
@Composable
fun BottomNavigation(navController: NavController) {
    val items = listOf(
        Screen.Chat,
        Screen.Models,
        Screen.Benchmark,
        Screen.Settings
    )

    NavigationBar {
        val navBackStackEntry by navController.currentBackStackEntryAsState()
        val currentRoute = navBackStackEntry?.destination?.route

        items.forEach { screen ->
            NavigationBarItem(
                icon = { Icon(screen.icon, contentDescription = null) },
                label = { Text(screen.title) },
                selected = currentRoute == screen.route,
                onClick = {
                    navController.navigate(screen.route) {
                        popUpTo(navController.graph.startDestinationId)
                        launchSingleTop = true
                    }
                }
            )
        }
    }
}

// Chat Screen
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    viewModel: ChatViewModel = hiltViewModel()
) {
    val messages by viewModel.messages.collectAsState()
    val isGenerating by viewModel.isGenerating.collectAsState()
    val selectedFramework by viewModel.selectedFramework.collectAsState()
    val currentModel by viewModel.currentModel.collectAsState()

    var inputText by remember { mutableStateOf("") }
    val scrollState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()

    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // Top Bar with Framework and Model Selection
        TopAppBar(
            title = { Text("Local LLM Chat") },
            actions = {
                // Framework selector
                Box {
                    var expanded by remember { mutableStateOf(false) }

                    IconButton(onClick = { expanded = true }) {
                        Icon(Icons.Default.Memory, contentDescription = "Select Framework")
                    }

                    DropdownMenu(
                        expanded = expanded,
                        onDismissRequest = { expanded = false }
                    ) {
                        LLMFramework.values().forEach { framework ->
                            DropdownMenuItem(
                                text = { Text(framework.displayName) },
                                onClick = {
                                    viewModel.selectFramework(framework)
                                    expanded = false
                                }
                            )
                        }
                    }
                }

                // Model selector
                currentModel?.let { model ->
                    Text(
                        text = model.name,
                        modifier = Modifier.padding(horizontal = 8.dp),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        )

        // Messages
        LazyColumn(
            state = scrollState,
            modifier = Modifier.weight(1f),
            reverseLayout = true
        ) {
            items(messages.reversed()) { message ->
                MessageItem(
                    message = message,
                    modifier = Modifier.padding(
                        horizontal = 16.dp,
                        vertical = 4.dp
                    )
                )
            }

            if (isGenerating) {
                item {
                    TypingIndicator(
                        modifier = Modifier.padding(16.dp)
                    )
                }
            }
        }

        // Input Bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = inputText,
                onValueChange = { inputText = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Type a message...") },
                enabled = !isGenerating,
                keyboardOptions = KeyboardOptions(
                    imeAction = ImeAction.Send
                ),
                keyboardActions = KeyboardActions(
                    onSend = {
                        if (inputText.isNotBlank() && !isGenerating) {
                            viewModel.sendMessage(inputText)
                            inputText = ""
                        }
                    }
                )
            )

            IconButton(
                onClick = {
                    if (inputText.isNotBlank() && !isGenerating) {
                        viewModel.sendMessage(inputText)
                        inputText = ""
                    }
                },
                enabled = inputText.isNotBlank() && !isGenerating
            ) {
                Icon(
                    Icons.Default.Send,
                    contentDescription = "Send",
                    tint = if (inputText.isNotBlank() && !isGenerating) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
                    }
                )
            }
        }
    }

    // Auto-scroll to bottom when new messages arrive
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            scrollState.animateScrollToItem(0)
        }
    }
}

// Message Item Component
@Composable
fun MessageItem(
    message: ChatMessage,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = if (message.role == ChatRole.USER) {
            Arrangement.End
        } else {
            Arrangement.Start
        }
    ) {
        Card(
            modifier = Modifier
                .widthIn(max = 280.dp)
                .padding(4.dp),
            colors = CardDefaults.cardColors(
                containerColor = if (message.role == ChatRole.USER) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.surfaceVariant
                }
            )
        ) {
            Column(
                modifier = Modifier.padding(12.dp)
            ) {
                Text(
                    text = message.content,
                    color = if (message.role == ChatRole.USER) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )

                Row(
                    modifier = Modifier.padding(top = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = SimpleDateFormat("HH:mm", Locale.getDefault())
                            .format(Date(message.timestamp)),
                        style = MaterialTheme.typography.bodySmall,
                        color = if (message.role == ChatRole.USER) {
                            MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.7f)
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                        }
                    )

                    message.metrics?.let { metrics ->
                        Text(
                            text = "${metrics.tokensPerSecond.toInt()} tok/s",
                            style = MaterialTheme.typography.bodySmall,
                            color = if (message.role == ChatRole.USER) {
                                MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.7f)
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                            }
                        )
                    }
                }
            }
        }
    }
}

// Model List Screen
@Composable
fun ModelListScreen(
    viewModel: ModelViewModel = hiltViewModel()
) {
    val downloadedModels by viewModel.downloadedModels.collectAsState()
    val availableModels by viewModel.availableModels.collectAsState()
    val downloadProgress by viewModel.downloadProgress.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Downloaded Models Section
        item {
            Text(
                text = "Downloaded Models",
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.padding(vertical = 8.dp)
            )
        }

        items(downloadedModels) { model ->
            ModelCard(
                model = model,
                isDownloaded = true,
                onDelete = { viewModel.deleteModel(model) }
            )
        }

        // Available Models Section
        item {
            Text(
                text = "Available Models",
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.padding(vertical = 8.dp)
            )
        }

        items(availableModels) { model ->
            ModelCard(
                model = model,
                isDownloaded = false,
                downloadProgress = downloadProgress[model.id],
                onDownload = { viewModel.downloadModel(model) }
            )
        }
    }
}

// Benchmark Screen
@Composable
fun BenchmarkScreen(
    viewModel: BenchmarkViewModel = hiltViewModel()
) {
    val selectedFrameworks by viewModel.selectedFrameworks.collectAsState()
    val selectedModel by viewModel.selectedModel.collectAsState()
    val isRunning by viewModel.isRunning.collectAsState()
    val results by viewModel.results.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Framework Selection
        Card {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                Text(
                    text = "Select Frameworks",
                    style = MaterialTheme.typography.titleMedium
                )

                LLMFramework.values().forEach { framework ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(
                            checked = framework in selectedFrameworks,
                            onCheckedChange = { checked ->
                                viewModel.toggleFramework(framework, checked)
                            }
                        )
                        Text(
                            text = framework.displayName,
                            modifier = Modifier.padding(start = 8.dp)
                        )
                    }
                }
            }
        }

        // Model Selection
        Card {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                Text(
                    text = "Select Model",
                    style = MaterialTheme.typography.titleMedium
                )

                // Model dropdown or list
                // ... implementation
            }
        }

        // Run Benchmark Button
        Button(
            onClick = { viewModel.runBenchmark() },
            modifier = Modifier.fillMaxWidth(),
            enabled = selectedFrameworks.isNotEmpty() &&
                     selectedModel != null &&
                     !isRunning
        ) {
            if (isRunning) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    color = MaterialTheme.colorScheme.onPrimary
                )
            } else {
                Text("Run Benchmark")
            }
        }

        // Results
        if (results.isNotEmpty()) {
            LazyColumn {
                items(results) { result ->
                    BenchmarkResultCard(result)
                }
            }
        }
    }
}
```

### Core Services Implementation

```kotlin
// Unified LLM Manager
@Singleton
class UnifiedLLMManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val services = mutableMapOf<LLMFramework, LLMService>()
    private var currentService: LLMService? = null

    init {
        registerServices()
    }

    private fun registerServices() {
        services[LLMFramework.GEMINI_NANO] = GeminiNanoService(context)
        services[LLMFramework.ONNX_RUNTIME] = ONNXRuntimeService(context)
        services[LLMFramework.EXECUTORCH] = ExecuTorchService(context)
        services[LLMFramework.MLC_LLM] = MLCService(context)
        services[LLMFramework.TFLITE] = TFLiteService(context)
        services[LLMFramework.MEDIAPIPE] = MediaPipeService(context)
        services[LLMFramework.LLAMA_CPP] = LlamaCppService(context)
        services[LLMFramework.PICOLLM] = PicoLLMService(context)
    }

    suspend fun selectFramework(
        framework: LLMFramework,
        modelPath: String
    ) = withContext(Dispatchers.IO) {
        currentService?.release()

        val service = services[framework]
            ?: throw IllegalArgumentException("Framework not supported")

        service.initialize(modelPath)
        currentService = service
    }

    suspend fun generate(
        prompt: String,
        options: GenerationOptions
    ): String = withContext(Dispatchers.Default) {
        currentService?.generate(prompt, options)
            ?: throw IllegalStateException("No service selected")
    }

    fun generateStream(
        prompt: String,
        options: GenerationOptions
    ): Flow<String> {
        return currentService?.generateStream(prompt, options)
            ?: flow { }
    }
}

// Chat ViewModel
@HiltViewModel
class ChatViewModel @Inject constructor(
    private val llmManager: UnifiedLLMManager,
    private val performanceMonitor: PerformanceMonitor
) : ViewModel() {
    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()

    private val _selectedFramework = MutableStateFlow(LLMFramework.MLC_LLM)
    val selectedFramework: StateFlow<LLMFramework> = _selectedFramework.asStateFlow()

    private val _currentModel = MutableStateFlow<ModelInfo?>(null)
    val currentModel: StateFlow<ModelInfo?> = _currentModel.asStateFlow()

    fun sendMessage(content: String) {
        viewModelScope.launch {
            // Add user message
            _messages.value += ChatMessage(
                role = ChatRole.USER,
                content = content,
                timestamp = System.currentTimeMillis()
            )

            _isGenerating.value = true
            performanceMonitor.startMeasurement()

            // Add assistant message placeholder
            val assistantMessage = ChatMessage(
                role = ChatRole.ASSISTANT,
                content = "",
                timestamp = System.currentTimeMillis()
            )
            _messages.value += assistantMessage

            try {
                // Stream generation
                llmManager.generateStream(
                    prompt = content,
                    options = GenerationOptions()
                ).collect { token ->
                    _messages.value = _messages.value.map { msg ->
                        if (msg == assistantMessage) {
                            msg.copy(content = msg.content + token)
                        } else msg
                    }
                    performanceMonitor.recordToken()
                }

                // Update with metrics
                val metrics = performanceMonitor.endMeasurement()
                _messages.value = _messages.value.map { msg ->
                    if (msg == assistantMessage) {
                        msg.copy(metrics = metrics)
                    } else msg
                }

            } catch (e: Exception) {
                _messages.value = _messages.value.map { msg ->
                    if (msg == assistantMessage) {
                        msg.copy(content = "Error: ${e.message}")
                    } else msg
                }
            } finally {
                _isGenerating.value = false
            }
        }
    }

    fun selectFramework(framework: LLMFramework) {
        _selectedFramework.value = framework

        _currentModel.value?.let { model ->
            viewModelScope.launch {
                try {
                    llmManager.selectFramework(framework, model.path)
                } catch (e: Exception) {
                    // Handle error
                    Log.e("ChatViewModel", "Failed to select framework", e)
                }
            }
        }
    }
}

// Model Repository
@Singleton
class ModelRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val modelDao: ModelDao
) {
    private val modelsDir = File(context.filesDir, "models")

    init {
        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
        }
    }

    suspend fun getDownloadedModels(): List<ModelInfo> {
        return modelDao.getAllModels()
    }

    suspend fun downloadModel(
        model: ModelInfo,
        onProgress: (Float) -> Unit
    ) = withContext(Dispatchers.IO) {
        val url = URL(model.downloadUrl)
        val connection = url.openConnection() as HttpURLConnection

        try {
            connection.connect()
            val fileLength = connection.contentLength

            val input = BufferedInputStream(connection.inputStream)
            val output = FileOutputStream(File(modelsDir, model.filename))

            val data = ByteArray(4096)
            var total = 0L
            var count: Int

            while (input.read(data).also { count = it } != -1) {
                total += count
                output.write(data, 0, count)

                if (fileLength > 0) {
                    onProgress((total.toFloat() / fileLength))
                }
            }

            output.flush()
            output.close()
            input.close()

            // Save to database
            modelDao.insertModel(model.copy(
                path = File(modelsDir, model.filename).absolutePath,
                downloadedAt = System.currentTimeMillis()
            ))

        } finally {
            connection.disconnect()
        }
    }
}
```

## 📊 Benchmark Implementation

### Benchmark Runner

```swift
// iOS Benchmark Runner
class BenchmarkRunner: ObservableObject {
    @Published var results: [BenchmarkResult] = []
    @Published var isRunning = false

    private let testPrompts = [
        "Write a simple Python function to calculate fibonacci numbers",
        "Explain quantum computing in simple terms",
        "What are the benefits of exercise?",
        "Translate 'Hello, how are you?' to Spanish",
        "Generate a haiku about technology"
    ]

    func runBenchmark(
        frameworks: [LLMFramework],
        model: ModelInfo
    ) async {
        isRunning = true
        results = []

        for framework in frameworks {
            let result = await benchmarkFramework(
                framework: framework,
                model: model
            )

            await MainActor.run {
                results.append(result)
            }
        }

        isRunning = false
    }

    private func benchmarkFramework(
        framework: LLMFramework,
        model: ModelInfo
    ) async -> BenchmarkResult {
        let service = createService(for: framework)

        do {
            // Initialize
            let initStart = Date()
            try await service.initialize(modelPath: model.path)
            let initTime = Date().timeIntervalSince(initStart)

            var promptResults: [PromptResult] = []

            // Test each prompt
            for prompt in testPrompts {
                let result = await benchmarkPrompt(
                    prompt: prompt,
                    service: service
                )
                promptResults.append(result)
            }

            // Cleanup
            service.cleanup()

            return BenchmarkResult(
                framework: framework,
                model: model,
                initializationTime: initTime,
                promptResults: promptResults,
                averageTokensPerSecond: calculateAverage(promptResults),
                totalMemoryUsed: getMemoryUsage()
            )

        } catch {
            return BenchmarkResult(
                framework: framework,
                model: model,
                error: error.localizedDescription
            )
        }
    }
}
```

```kotlin
// Android Benchmark Implementation
@HiltViewModel
class BenchmarkViewModel @Inject constructor(
    private val llmManager: UnifiedLLMManager
) : ViewModel() {
    private val _results = MutableStateFlow<List<BenchmarkResult>>(emptyList())
    val results: StateFlow<List<BenchmarkResult>> = _results.asStateFlow()

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    private val testPrompts = listOf(
        "Write a simple Python function to calculate fibonacci numbers",
        "Explain quantum computing in simple terms",
        "What are the benefits of exercise?",
        "Translate 'Hello, how are you?' to Spanish",
        "Generate a haiku about technology"
    )

    fun runBenchmark() {
        viewModelScope.launch {
            _isRunning.value = true
            _results.value = emptyList()

            for (framework in selectedFrameworks.value) {
                val result = benchmarkFramework(framework)
                _results.value += result
            }

            _isRunning.value = false
        }
    }

    private suspend fun benchmarkFramework(
        framework: LLMFramework
    ): BenchmarkResult = withContext(Dispatchers.Default) {
        try {
            // Initialize
            val initStart = System.currentTimeMillis()
            llmManager.selectFramework(framework, selectedModel.value!!.path)
            val initTime = System.currentTimeMillis() - initStart

            val promptResults = mutableListOf<PromptResult>()

            // Test each prompt
            for (prompt in testPrompts) {
                val result = benchmarkPrompt(prompt)
                promptResults.add(result)
            }

            BenchmarkResult(
                framework = framework,
                model = selectedModel.value!!,
                initializationTime = initTime,
                promptResults = promptResults,
                averageTokensPerSecond = calculateAverage(promptResults),
                memoryUsed = getMemoryUsage()
            )

        } catch (e: Exception) {
            BenchmarkResult(
                framework = framework,
                model = selectedModel.value!!,
                error = e.message
            )
        }
    }
}
```

## 🎨 UI Components

### Shared Components

```swift
// iOS Typing Indicator
struct TypingIndicator: View {
    @State private var animationAmount = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationAmount)
                    .opacity(animationAmount)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animationAmount
                    )
            }
        }
        .onAppear {
            animationAmount = 1.0
        }
    }
}
```

```kotlin
// Android Typing Indicator
@Composable
fun TypingIndicator(
    modifier: Modifier = Modifier
) {
    val infiniteTransition = rememberInfiniteTransition()

    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        repeat(3) { index ->
            val alpha by infiniteTransition.animateFloat(
                initialValue = 0.3f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = keyframes {
                        durationMillis = 1200
                        0.3f at 0
                        1f at 600
                        0.3f at 1200
                    },
                    repeatMode = RepeatMode.Restart,
                    initialStartOffset = StartOffset(index * 400)
                )
            )

            Box(
                modifier = Modifier
                    .size(8.dp)
                    .background(
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = alpha),
                        shape = CircleShape
                    )
            )
        }
    }
}
```

## 🚀 Model Download & Management

### Model Downloader Implementation

```swift
// iOS Model Downloader
class ModelDownloader: ObservableObject {
    func download(
        url: URL,
        to destination: URL
    ) -> AsyncThrowingStream<Float, Error> {
        AsyncThrowingStream { continuation in
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let location = location else {
                    continuation.finish(throwing: DownloadError.noData)
                    return
                }

                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Progress observation
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                continuation.yield(Float(progress.fractionCompleted))
            }

            task.resume()

            continuation.onTermination = { _ in
                observation.invalidate()
                task.cancel()
            }
        }
    }
}
```

```kotlin
// Android Model Downloader
class ModelDownloader @Inject constructor(
    @ApplicationContext private val context: Context
) {
    suspend fun downloadModel(
        url: String,
        fileName: String,
        onProgress: (Float) -> Unit
    ): File = withContext(Dispatchers.IO) {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        val request = Request.Builder()
            .url(url)
            .build()

        val response = client.newCall(request).execute()

        if (!response.isSuccessful) {
            throw IOException("Failed to download model: ${response.code}")
        }

        val file = File(context.filesDir, "models/$fileName")
        file.parentFile?.mkdirs()

        response.body?.let { body ->
            val contentLength = body.contentLength()
            val source = body.source()
            val sink = file.sink().buffer()

            var totalBytesRead = 0L
            val bufferSize = 8 * 1024L

            while (true) {
                val bytesRead = source.read(sink.buffer, bufferSize)
                if (bytesRead == -1L) break

                sink.emit()
                totalBytesRead += bytesRead

                if (contentLength > 0) {
                    val progress = totalBytesRead.toFloat() / contentLength
                    withContext(Dispatchers.Main) {
                        onProgress(progress)
                    }
                }
            }

            sink.close()
            source.close()
        }

        file
    }
}
```

## 📈 Performance Monitoring

### Unified Performance Monitor

```swift
// iOS Performance Monitor
class PerformanceMonitor {
    private var startTime: CFAbsoluteTime = 0
    private var firstTokenTime: CFAbsoluteTime = 0
    private var tokenCount = 0
    private var startMemory = 0

    func startMeasurement() {
        startTime = CFAbsoluteTimeGetCurrent()
        firstTokenTime = 0
        tokenCount = 0
        startMemory = getMemoryUsage()
    }

    func recordFirstToken() {
        if firstTokenTime == 0 {
            firstTokenTime = CFAbsoluteTimeGetCurrent()
        }
    }

    func recordToken() {
        tokenCount += 1
        recordFirstToken()
    }

    func endMeasurement() -> PerformanceMetrics {
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        let timeToFirstToken = firstTokenTime > 0 ? firstTokenTime - startTime : 0
        let tokensPerSecond = Double(tokenCount) / totalTime
        let memoryUsed = getMemoryUsage() - startMemory

        return PerformanceMetrics(
            totalTime: totalTime,
            timeToFirstToken: timeToFirstToken,
            tokensPerSecond: tokensPerSecond,
            tokenCount: tokenCount,
            memoryUsed: memoryUsed,
            cpuUsage: getCurrentCPUUsage(),
            batteryLevel: UIDevice.current.batteryLevel
        )
    }

    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}
```

```kotlin
// Android Performance Monitor
@Singleton
class PerformanceMonitor @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var startTime = 0L
    private var firstTokenTime = 0L
    private var tokenCount = 0
    private var startMemory = 0L

    fun startMeasurement() {
        startTime = System.currentTimeMillis()
        firstTokenTime = 0L
        tokenCount = 0
        startMemory = getMemoryUsage()
    }

    fun recordFirstToken() {
        if (firstTokenTime == 0L) {
            firstTokenTime = System.currentTimeMillis()
        }
    }

    fun recordToken() {
        tokenCount++
        recordFirstToken()
    }

    fun endMeasurement(): PerformanceMetrics {
        val endTime = System.currentTimeMillis()
        val totalTime = endTime - startTime
        val timeToFirstToken = if (firstTokenTime > 0) firstTokenTime - startTime else 0
        val tokensPerSecond = tokenCount.toFloat() / (totalTime / 1000f)
        val memoryUsed = getMemoryUsage() - startMemory

        return PerformanceMetrics(
            totalTime = totalTime,
            timeToFirstToken = timeToFirstToken,
            tokensPerSecond = tokensPerSecond,
            tokenCount = tokenCount,
            memoryUsed = memoryUsed,
            cpuUsage = getCpuUsage(),
            batteryLevel = getBatteryLevel()
        )
    }

    private fun getMemoryUsage(): Long {
        val runtime = Runtime.getRuntime()
        return runtime.totalMemory() - runtime.freeMemory()
    }

    private fun getCpuUsage(): Float {
        // Implementation for CPU usage
        return 0f
    }

    private fun getBatteryLevel(): Float {
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) / 100f
    }
}
```

## 🔧 Configuration & Settings

### Framework-Specific Settings

```swift
// iOS Settings View
struct SettingsView: View {
    @AppStorage("defaultFramework") private var defaultFramework = LLMFramework.mlc.rawValue
    @AppStorage("maxTokens") private var maxTokens = 150
    @AppStorage("temperature") private var temperature = 0.7
    @AppStorage("enableStreaming") private var enableStreaming = true

    var body: some View {
        NavigationView {
            Form {
                Section("General") {
                    Picker("Default Framework", selection: $defaultFramework) {
                        ForEach(LLMFramework.allCases, id: \.self) { framework in
                            Text(framework.displayName).tag(framework.rawValue)
                        }
                    }

                    Stepper("Max Tokens: \(maxTokens)", value: $maxTokens, in: 50...500, step: 50)

                    VStack(alignment: .leading) {
                        Text("Temperature: \(String(format: "%.1f", temperature))")
                        Slider(value: $temperature, in: 0...1, step: 0.1)
                    }

                    Toggle("Enable Streaming", isOn: $enableStreaming)
                }

                Section("Performance") {
                    NavigationLink("Memory Management") {
                        MemorySettingsView()
                    }

                    NavigationLink("Battery Optimization") {
                        BatterySettingsView()
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundColor(.secondary)
                    }

                    Link("Documentation", destination: URL(string: "https://docs.example.com")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

```kotlin
// Android Settings Screen
@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val preferences = remember {
        context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    }

    var defaultFramework by remember {
        mutableStateOf(
            LLMFramework.valueOf(
                preferences.getString("defaultFramework", LLMFramework.MLC_LLM.name)
                    ?: LLMFramework.MLC_LLM.name
            )
        )
    }

    var maxTokens by remember {
        mutableStateOf(preferences.getInt("maxTokens", 150))
    }

    var temperature by remember {
        mutableStateOf(preferences.getFloat("temperature", 0.7f))
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp)
    ) {
        item {
            Text(
                text = "General Settings",
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.padding(vertical = 8.dp)
            )
        }

        item {
            Card {
                Column(
                    modifier = Modifier.padding(16.dp)
                ) {
                    // Default Framework
                    Text("Default Framework")

                    var expanded by remember { mutableStateOf(false) }

                    ExposedDropdownMenuBox(
                        expanded = expanded,
                        onExpandedChange = { expanded = it }
                    ) {
                        TextField(
                            value = defaultFramework.displayName,
                            onValueChange = {},
                            readOnly = true,
                            trailingIcon = {
                                ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded)
                            },
                            modifier = Modifier.menuAnchor()
                        )

                        ExposedDropdownMenu(
                            expanded = expanded,
                            onDismissRequest = { expanded = false }
                        ) {
                            LLMFramework.values().forEach { framework ->
                                DropdownMenuItem(
                                    text = { Text(framework.displayName) },
                                    onClick = {
                                        defaultFramework = framework
                                        preferences.edit()
                                            .putString("defaultFramework", framework.name)
                                            .apply()
                                        expanded = false
                                    }
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Max Tokens
                    Text("Max Tokens: $maxTokens")
                    Slider(
                        value = maxTokens.toFloat(),
                        onValueChange = {
                            maxTokens = it.toInt()
                            preferences.edit()
                                .putInt("maxTokens", maxTokens)
                                .apply()
                        },
                        valueRange = 50f..500f,
                        steps = 9
                    )

                    Spacer(modifier = Modifier.height(16.dp))

                    // Temperature
                    Text("Temperature: %.1f".format(temperature))
                    Slider(
                        value = temperature,
                        onValueChange = {
                            temperature = it
                            preferences.edit()
                                .putFloat("temperature", temperature)
                                .apply()
                        },
                        valueRange = 0f..1f,
                        steps = 9
                    )
                }
            }
        }
    }
}
```

## 🚦 Getting Started

### iOS Setup

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/LocalLLMiOS.git
cd LocalLLMiOS
```

2. **Install dependencies**
```bash
# If using CocoaPods
pod install

# If using Swift Package Manager
# Dependencies will be resolved automatically in Xcode
```

3. **Configure frameworks**
- Add framework-specific API keys to `Config.plist`
- Download initial models or use bundled ones

4. **Build and run**
```bash
open LocalLLMiOS.xcworkspace
# Build and run in Xcode
```

### Android Setup

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/LocalLLMAndroid.git
cd LocalLLMAndroid
```

2. **Configure Gradle**
```gradle
// In local.properties
GEMINI_API_KEY=your_api_key_here
PICOLLM_ACCESS_KEY=your_access_key_here
```

3. **Build and run**
```bash
./gradlew assembleDebug
./gradlew installDebug
```

## 📝 Best Practices

### Memory Management
- Monitor memory usage continuously
- Implement proper cleanup in `onDestroy`/`deinit`
- Use lazy loading for models
- Clear caches when entering background

### Performance Optimization
- Use appropriate quantization levels
- Select frameworks based on device capabilities
- Implement thermal throttling
- Batch requests when possible

### User Experience
- Show clear loading states
- Provide progress indicators for downloads
- Handle errors gracefully
- Save conversation history

### Security
- Store models securely
- Validate model integrity
- Handle sensitive data appropriately
- Implement proper permissions

## 🎯 Conclusion

This comprehensive implementation guide provides everything needed to build production-ready sample apps demonstrating local LLM capabilities on both iOS and Android platforms. The modular architecture makes it easy to add new frameworks, while the unified interface ensures consistent user experience across all implementations.

Key takeaways:
- **Framework abstraction** enables easy switching and comparison
- **Performance monitoring** provides insights into real-world usage
- **Comprehensive UI** showcases all framework capabilities
- **Production-ready architecture** can be extended for real applications

The sample apps serve as both educational resources and starting points for building production applications with local LLM capabilities.
