# Native App Quick Start Guide - Local LLM Implementation

## 🚀 Overview

This guide focuses on quickly implementing local LLM capabilities in native iOS and Android apps using readily available, pre-converted models. No model conversion needed - just download and run!

## 📦 Available Pre-Converted Models

### Universal Models (Work Across Frameworks)

| Model | Size | Download Link | Supported Frameworks |
|-------|------|---------------|---------------------|
| **Llama 3.2 3B** | 1.7GB | [HuggingFace Hub](https://huggingface.co/models) | GGUF, MLC, ExecuTorch |
| **Phi-3 Mini** | 1.5GB | [Microsoft](https://huggingface.co/microsoft/Phi-3-mini-4k-instruct) | ONNX, Core ML, GGUF |
| **Gemma 2B** | 1.1GB | [Google](https://huggingface.co/google/gemma-2b) | MediaPipe, TFLite |
| **TinyLlama 1.1B** | 550MB | [HuggingFace](https://huggingface.co/TinyLlama/TinyLlama-1.1B-Chat-v1.0) | All formats |
| **Mistral 7B** | 3.8GB | [Mistral AI](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.3) | GGUF, MLC |

### Framework-Specific Model Sources

#### iOS Models
- **Core ML Models**: [Apple Model Gallery](https://developer.apple.com/machine-learning/models/)
- **MLX Models**: [MLX Community](https://huggingface.co/mlx-community)
- **MLC Models**: [MLC-LLM Prebuilts](https://llm.mlc.ai/prebuilt)

#### Android Models
- **Gemini Nano**: Built into Android 14+ (no download needed)
- **MediaPipe Models**: [MediaPipe Model Downloads](https://developers.google.com/mediapipe/solutions/genai/llm_inference#models)
- **GGUF Models**: [TheBloke's Quantized Models](https://huggingface.co/TheBloke)

## 🏃‍♂️ iOS Quick Start

### Step 1: Create New iOS Project

```bash
# Create new Xcode project
# Select: iOS > App > SwiftUI
# Name: LocalLLMDemo
```

### Step 2: Add Dependencies

**Option A: Swift Package Manager (Recommended)**

```swift
// In Xcode: File > Add Package Dependencies
// Add these URLs:

// For MLC-LLM
https://github.com/mlc-ai/mlc-swift

// For MLX
https://github.com/ml-explore/mlx-swift
https://github.com/ml-explore/mlx-swift-examples

// For ONNX Runtime
https://github.com/microsoft/onnxruntime
```

**Option B: CocoaPods**

```ruby
# Podfile
platform :ios, '14.0'
use_frameworks!

target 'LocalLLMDemo' do
  pod 'MLCSwift', '~> 0.1.0'
  pod 'ONNX-Runtime-Mobile'
end
```

### Step 3: Basic Implementation

```swift
import SwiftUI
import MLCSwift

// 1. Main App
@main
struct LocalLLMDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// 2. Content View
struct ContentView: View {
    @StateObject private var chatModel = ChatModel()
    @State private var inputText = ""
    @State private var messages: [Message] = []
    
    var body: some View {
        VStack {
            // Chat messages
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        HStack {
                            if message.isUser {
                                Spacer()
                            }
                            
                            Text(message.content)
                                .padding(10)
                                .background(message.isUser ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(message.isUser ? .white : .primary)
                                .cornerRadius(10)
                            
                            if !message.isUser {
                                Spacer()
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            // Input field
            HStack {
                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Send") {
                    sendMessage()
                }
                .disabled(inputText.isEmpty || chatModel.isGenerating)
            }
            .padding()
        }
        .onAppear {
            chatModel.initialize()
        }
    }
    
    func sendMessage() {
        let userMessage = Message(content: inputText, isUser: true)
        messages.append(userMessage)
        
        let prompt = inputText
        inputText = ""
        
        // Add AI message placeholder
        let aiMessage = Message(content: "", isUser: false)
        messages.append(aiMessage)
        
        Task {
            var response = ""
            for await token in chatModel.generate(prompt: prompt) {
                response += token
                // Update last message
                if let index = messages.lastIndex(where: { !$0.isUser }) {
                    messages[index].content = response
                }
            }
        }
    }
}

// 3. Chat Model
class ChatModel: ObservableObject {
    @Published var isGenerating = false
    private var engine: MLCEngine?
    
    func initialize() {
        Task {
            do {
                // Download model if needed
                let modelPath = await downloadModelIfNeeded()
                
                // Initialize MLC engine
                let config = MLCEngineConfig(
                    model: modelPath,
                    device: .auto
                )
                
                engine = try await MLCEngine(config: config)
                print("Model loaded successfully!")
            } catch {
                print("Failed to load model: \(error)")
            }
        }
    }
    
    func generate(prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                isGenerating = true
                
                do {
                    let request = ChatCompletionRequest(
                        messages: [
                            ChatMessage(role: .user, content: prompt)
                        ],
                        stream: true
                    )
                    
                    for try await chunk in engine!.streamChatCompletion(request) {
                        if let content = chunk.choices.first?.delta.content {
                            continuation.yield(content)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    print("Generation error: \(error)")
                    continuation.finish()
                }
                
                isGenerating = false
            }
        }
    }
    
    private func downloadModelIfNeeded() async -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelPath = documentsPath.appendingPathComponent("phi-3-mini-q4.mlc")
        
        // Check if model exists
        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath.path
        }
        
        // Download model (simplified - in production use proper downloader)
        let modelURL = URL(string: "https://huggingface.co/mlc-ai/phi-3-mini-4k-instruct-q4f16_1-MLC/resolve/main/model.tar")!
        
        do {
            let (localURL, _) = try await URLSession.shared.download(from: modelURL)
            try FileManager.default.moveItem(at: localURL, to: modelPath)
            return modelPath.path
        } catch {
            print("Download failed: \(error)")
            // Return path to bundled model as fallback
            return Bundle.main.path(forResource: "tinyllama-q4", ofType: "mlc") ?? ""
        }
    }
}

// 4. Message Model
struct Message: Identifiable {
    let id = UUID()
    var content: String
    let isUser: Bool
}
```

### Step 4: Add Pre-Downloaded Model (Optional)

1. Download a model from the sources above
2. Drag the model file into your Xcode project
3. Make sure "Copy items if needed" is checked
4. Update the model path in code:

```swift
// Use bundled model
let modelPath = Bundle.main.path(forResource: "tinyllama-q4", ofType: "mlc")!
```

## 🤖 Android Quick Start

### Step 1: Create New Android Project

```kotlin
// Android Studio: New Project
// Select: Phone and Tablet > Empty Activity
// Name: LocalLLMDemo
// Language: Kotlin
// Minimum SDK: API 24
```

### Step 2: Add Dependencies

```gradle
// app/build.gradle.kts

dependencies {
    // Gemini Nano (for supported devices)
    implementation("com.google.ai.edge:genai:1.0.0")
    
    // ONNX Runtime (universal)
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.19.0")
    
    // MLC-LLM
    implementation("org.mlc:mlc-llm:0.1.0")
    
    // Jetpack Compose
    implementation("androidx.compose.ui:ui:1.5.4")
    implementation("androidx.compose.material3:material3:1.1.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    
    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
```

### Step 3: Basic Implementation

```kotlin
// 1. MainActivity.kt
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.localllmdemo.ui.theme.LocalLLMDemoTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            LocalLLMDemoTheme {
                ChatScreen()
            }
        }
    }
}

// 2. ChatScreen.kt
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    viewModel: ChatViewModel = viewModel()
) {
    val messages by viewModel.messages.collectAsState()
    val isGenerating by viewModel.isGenerating.collectAsState()
    var inputText by remember { mutableStateOf("") }
    
    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // Top bar
        TopAppBar(
            title = { Text("Local LLM Chat") }
        )
        
        // Messages
        LazyColumn(
            modifier = Modifier.weight(1f),
            reverseLayout = true
        ) {
            items(messages.reversed()) { message ->
                MessageBubble(message)
            }
        }
        
        // Input
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextField(
                value = inputText,
                onValueChange = { inputText = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Type a message...") },
                enabled = !isGenerating
            )
            
            IconButton(
                onClick = {
                    if (inputText.isNotBlank()) {
                        viewModel.sendMessage(inputText)
                        inputText = ""
                    }
                },
                enabled = inputText.isNotBlank() && !isGenerating
            ) {
                Icon(Icons.Default.Send, contentDescription = "Send")
            }
        }
    }
}

// 3. MessageBubble.kt
@Composable
fun MessageBubble(message: Message) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp),
        horizontalArrangement = if (message.isUser) {
            Arrangement.End
        } else {
            Arrangement.Start
        }
    ) {
        Card(
            modifier = Modifier.widthIn(max = 280.dp),
            colors = CardDefaults.cardColors(
                containerColor = if (message.isUser) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.surfaceVariant
                }
            )
        ) {
            Text(
                text = message.content,
                modifier = Modifier.padding(12.dp),
                color = if (message.isUser) {
                    MaterialTheme.colorScheme.onPrimary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
        }
    }
}

// 4. ChatViewModel.kt
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import org.mlc.llm.*

class ChatViewModel : ViewModel() {
    private val _messages = MutableStateFlow<List<Message>>(emptyList())
    val messages: StateFlow<List<Message>> = _messages.asStateFlow()
    
    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()
    
    private var mlcEngine: MLCEngine? = null
    
    init {
        initializeModel()
    }
    
    private fun initializeModel() {
        viewModelScope.launch {
            try {
                // Use pre-downloaded model or download
                val modelPath = getModelPath()
                
                val config = MLCEngineConfig().apply {
                    model = modelPath
                    device = DeviceKind.AUTO
                }
                
                mlcEngine = MLCEngine(config)
                println("Model loaded successfully!")
            } catch (e: Exception) {
                println("Failed to load model: ${e.message}")
            }
        }
    }
    
    fun sendMessage(content: String) {
        viewModelScope.launch {
            // Add user message
            _messages.value += Message(
                content = content,
                isUser = true
            )
            
            // Add AI message placeholder
            val aiMessage = Message(
                content = "",
                isUser = false
            )
            _messages.value += aiMessage
            
            _isGenerating.value = true
            
            try {
                // Generate response
                val request = ChatCompletionRequest(
                    messages = listOf(
                        Message(role = "user", content = content)
                    ),
                    stream = true
                )
                
                var response = ""
                mlcEngine?.streamChatCompletion(request) { chunk ->
                    chunk.choices.firstOrNull()?.delta?.content?.let { token ->
                        response += token
                        // Update AI message
                        _messages.value = _messages.value.map { msg ->
                            if (msg == aiMessage) {
                                msg.copy(content = response)
                            } else msg
                        }
                    }
                }
            } catch (e: Exception) {
                _messages.value = _messages.value.map { msg ->
                    if (msg == aiMessage) {
                        msg.copy(content = "Error: ${e.message}")
                    } else msg
                }
            } finally {
                _isGenerating.value = false
            }
        }
    }
    
    private suspend fun getModelPath(): String {
        // Check if model exists in app files
        val modelFile = File(context.filesDir, "tinyllama-q4.mlc")
        
        if (modelFile.exists()) {
            return modelFile.absolutePath
        }
        
        // Copy from assets (if bundled)
        try {
            context.assets.open("tinyllama-q4.mlc").use { input ->
                modelFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            return modelFile.absolutePath
        } catch (e: Exception) {
            // Download model
            return downloadModel()
        }
    }
}

// 5. Message.kt
data class Message(
    val id: String = UUID.randomUUID().toString(),
    val content: String,
    val isUser: Boolean,
    val timestamp: Long = System.currentTimeMillis()
)
```

### Step 4: Add Model to Assets (Optional)

1. Download a small model (e.g., TinyLlama GGUF)
2. Create `app/src/main/assets` folder
3. Copy model file there
4. Access in code:

```kotlin
// Load from assets
context.assets.open("model.gguf").use { input ->
    File(context.filesDir, "model.gguf").outputStream().use { output ->
        input.copyTo(output)
    }
}
```

## 🎯 Framework Selection Guide

### For iOS

| If you want... | Use this framework | Model format |
|----------------|-------------------|--------------|
| Easiest setup | MLC-LLM | .mlc files |
| Best performance | MLX (Apple Silicon) | .mlx files |
| Smallest size | llama.cpp | .gguf files |
| Apple integration | Core ML | .mlpackage |

### For Android

| If you want... | Use this framework | Model format |
|----------------|-------------------|--------------|
| Google integration | Gemini Nano | Built-in |
| Cross-platform | ONNX Runtime | .onnx files |
| Best performance | ExecuTorch | .pte files |
| Smallest size | llama.cpp | .gguf files |

## 📱 Complete Minimal Examples

### iOS - Minimal Chat App (100 lines)

```swift
import SwiftUI
import MLCSwift

@main
struct QuickLLMApp: App {
    var body: some Scene {
        WindowGroup {
            ChatView()
        }
    }
}

struct ChatView: View {
    @State private var messages: [(String, Bool)] = []
    @State private var input = ""
    @State private var engine: MLCEngine?
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(Array(messages.enumerated()), id: \.0) { _, message in
                    HStack {
                        if message.1 { Spacer() }
                        Text(message.0)
                            .padding(8)
                            .background(message.1 ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        if !message.1 { Spacer() }
                    }
                    .padding(.horizontal)
                }
            }
            
            HStack {
                TextField("Message", text: $input)
                Button("Send") { send() }
            }
            .padding()
        }
        .task { await setup() }
    }
    
    func setup() async {
        do {
            engine = try await MLCEngine(
                MLCEngineConfig(
                    model: Bundle.main.path(forResource: "model", ofType: "mlc")!,
                    device: .auto
                )
            )
        } catch {
            print("Setup failed: \(error)")
        }
    }
    
    func send() {
        let prompt = input
        messages.append((prompt, true))
        messages.append(("", false))
        input = ""
        
        Task {
            var response = ""
            for try await chunk in engine!.streamChatCompletion(
                ChatCompletionRequest(
                    messages: [ChatMessage(role: .user, content: prompt)],
                    stream: true
                )
            ) {
                if let content = chunk.choices.first?.delta.content {
                    response += content
                    messages[messages.count - 1].0 = response
                }
            }
        }
    }
}
```

### Android - Minimal Chat App (100 lines)

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ChatApp()
        }
    }
}

@Composable
fun ChatApp() {
    var messages by remember { mutableStateOf(listOf<Pair<String, Boolean>>()) }
    var input by remember { mutableStateOf("") }
    val engine = remember { mutableStateOf<MLCEngine?>(null) }
    
    LaunchedEffect(Unit) {
        try {
            engine.value = MLCEngine(
                MLCEngineConfig().apply {
                    model = "/data/local/tmp/model.mlc"
                    device = DeviceKind.AUTO
                }
            )
        } catch (e: Exception) {
            println("Setup failed: $e")
        }
    }
    
    Column(Modifier.fillMaxSize()) {
        LazyColumn(
            Modifier.weight(1f),
            reverseLayout = true
        ) {
            items(messages.reversed()) { (text, isUser) ->
                Row(
                    Modifier.fillMaxWidth().padding(8.dp),
                    horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
                ) {
                    Card(
                        colors = CardDefaults.cardColors(
                            if (isUser) Color.Blue else Color.Gray
                        )
                    ) {
                        Text(
                            text,
                            Modifier.padding(8.dp),
                            color = Color.White
                        )
                    }
                }
            }
        }
        
        Row(Modifier.padding(8.dp)) {
            TextField(
                value = input,
                onValueChange = { input = it },
                Modifier.weight(1f)
            )
            Button(
                onClick = {
                    val prompt = input
                    messages = messages + (prompt to true) + ("" to false)
                    input = ""
                    
                    GlobalScope.launch {
                        var response = ""
                        engine.value?.streamChatCompletion(
                            ChatCompletionRequest(
                                messages = listOf(
                                    Message("user", prompt)
                                ),
                                stream = true
                            )
                        ) { chunk ->
                            chunk.choices.firstOrNull()?.delta?.content?.let {
                                response += it
                                messages = messages.dropLast(1) + (response to false)
                            }
                        }
                    }
                }
            ) {
                Text("Send")
            }
        }
    }
}
```

## 🚀 Deployment Tips

### iOS
1. **App Store**: Models under 200MB can be bundled
2. **On-Demand Resources**: For larger models
3. **CloudKit**: For model updates
4. **TestFlight**: Test with real devices

### Android
1. **Play Store**: Use Play Asset Delivery for large models
2. **APK Splits**: Reduce download size
3. **Dynamic Delivery**: Download models after install
4. **Internal Testing**: Use Play Console testing tracks

## 📊 Performance Quick Wins

### Both Platforms
- Start with smallest quantized models (Q4)
- Use streaming for better UX
- Implement proper error handling
- Cache model in app storage
- Monitor memory usage

### iOS Specific
- Use `.mlpackage` format for Core ML
- Enable GPU acceleration
- Leverage Neural Engine on A12+

### Android Specific
- Use NNAPI for acceleration
- Target latest Android versions
- Test on various chipsets
- Use ProGuard rules for optimization

## 🎉 You're Ready!

With this guide, you can have a working local LLM chat app running in under an hour on both platforms. Start with the minimal examples, then expand based on your needs.

### Next Steps
1. Try different models from the pre-converted sources
2. Add more UI features (typing indicators, timestamps)
3. Implement conversation history
4. Add model switching in-app
5. Optimize for your specific use case

Remember: Start small with TinyLlama or Phi-3, then scale up as needed!