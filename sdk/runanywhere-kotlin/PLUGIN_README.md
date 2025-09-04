# RunAnywhere SDK Plugin - Quick Start Guide

## 🚀 For Team Members - Quick Commands

### Install and Run in Android Studio
```bash
# Navigate to SDK directory
cd sdk/runanywhere-kotlin

# Build and run in Android Studio (opens automatically)
./scripts/sdk.sh run-plugin-as

# Or just build the plugin (creates ZIP file)
./scripts/sdk.sh plugin-as
```

### Install and Run in IntelliJ IDEA
```bash
# Build and run in IntelliJ IDEA
./scripts/sdk.sh run-plugin

# Or just build the plugin
./scripts/sdk.sh plugin
```

## 📦 Manual Installation

If you prefer to install manually:

1. **Build the plugin:**
   ```bash
   ./scripts/sdk.sh plugin-as  # For Android Studio
   # OR
   ./scripts/sdk.sh plugin     # For IntelliJ IDEA
   ```

2. **Install in your IDE:**
   - Open Android Studio/IntelliJ IDEA
   - Go to `File` → `Settings` → `Plugins`
   - Click gear icon ⚙️ → `Install Plugin from Disk`
   - Select: `examples/intellij-plugin-demo/plugin/build/distributions/runanywhere-voice-1.0.0.zip`
   - Restart IDE

## 🧪 Testing the SDK Integration

Once installed, test the SDK:

1. **Open any project** in your IDE
2. **Go to Tools menu** → **Test RunAnywhere SDK**
3. **Or use shortcut:** `Ctrl+Shift+T` (Windows/Linux) or `Cmd+Shift+T` (Mac)

You should see a dialog showing:
- ✅ SDK Initialization status
- 📦 SDK Version (0.1.0)
- 🎯 Environment (Development)
- Available components

## 🛠️ All Available Commands

```bash
# Core SDK Commands
./scripts/sdk.sh jvm           # Build JVM SDK only
./scripts/sdk.sh clean          # Clean all build artifacts

# Plugin Commands
./scripts/sdk.sh plugin         # Build for IntelliJ IDEA
./scripts/sdk.sh plugin-as      # Build for Android Studio
./scripts/sdk.sh run-plugin     # Build & run IntelliJ IDEA
./scripts/sdk.sh run-plugin-as  # Build & run Android Studio

# Other Commands
./scripts/sdk.sh help           # Show all commands
./scripts/sdk.sh info           # Show SDK info
```

## 📁 Project Structure

```
sdk/runanywhere-kotlin/
├── scripts/
│   ├── sdk.sh           # Main build script
│   └── detect-ide.sh    # Auto-detects installed IDEs
├── src/
│   ├── commonMain/      # Shared code
│   ├── jvmMain/         # JVM-specific code
│   └── androidMain/     # Android-specific code
└── build/
    └── libs/            # Built JARs

examples/intellij-plugin-demo/
└── plugin/
    ├── src/             # Plugin source code
    └── build/
        └── distributions/  # Plugin ZIP files
```

## 🔧 Troubleshooting

### Plugin doesn't appear in Tools menu
- Restart the IDE after installation
- Check `File` → `Settings` → `Plugins` → Installed tab

### Build fails
```bash
# Clean and rebuild
./scripts/sdk.sh clean
./scripts/sdk.sh plugin-as
```

### Can't find script
Make sure you're in the right directory:
```bash
cd sdk/runanywhere-kotlin
ls scripts/  # Should show sdk.sh
```

## 💡 Tips

- The script automatically detects your installed IDE version
- The plugin works in both Android Studio and IntelliJ IDEA
- SDK is published to local Maven (~/.m2/repository)
- Plugin ZIP is created in: `examples/intellij-plugin-demo/plugin/build/distributions/`

## 📝 For Developers

### Adding New SDK Features

1. Add feature in `sdk/runanywhere-kotlin/src/commonMain/`
2. Build SDK: `./scripts/sdk.sh jvm`
3. Test in plugin: `./scripts/sdk.sh run-plugin-as`

### Modifying the Plugin

Plugin source: `examples/intellij-plugin-demo/plugin/src/main/kotlin/`
- `SDKTestAction.kt` - Test action demonstrating SDK usage
- `plugin.xml` - Plugin configuration

### SDK Maven Coordinates
```kotlin
dependencies {
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
}
```

---

**Questions?** The script is self-documenting - run `./scripts/sdk.sh help` for all options!
