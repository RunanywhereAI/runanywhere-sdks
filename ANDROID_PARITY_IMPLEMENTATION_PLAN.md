# Android Sample App - Text-to-Text Generation Parity Plan

**Created**: October 8, 2025
**Last Updated**: October 8, 2025
**Focus**: Bare minimum text-to-text generation with iOS visual parity
**SDK Status**: ✅ Fully implemented (Phases 0-4 complete)
**Timeline**: 10 days

---

## 🎯 Executive Summary

### Current State
- **Kotlin SDK**: ✅ 100% ready for text-to-text (all phases complete)
- **Android App**: Has UI foundations but **NOT wired to SDK**
- **Critical Gap**: App uses **placeholder/mock data** instead of real SDK calls

### What's Working
- ✅ Model Management UI (downloads, progress tracking)
- ✅ Chat UI design (message bubbles, input)
- ✅ Material Design 3 theming
- ✅ Navigation structure

### What's Broken (Critical)
1. ❌ SDK not initialized in app
2. ❌ Chat generation uses placeholder text
3. ❌ Model downloads not wired to SDK
4. ❌ No conversation persistence
5. ❌ No settings screen
6. ❌ Plain text only (no markdown)

### Success Criteria
After this plan, the Android app should:
1. ✅ Initialize SDK correctly
2. ✅ Download and load models from SDK
3. ✅ Generate real text responses (streaming)
4. ✅ Display analytics (tokens/sec, TTFT)
5. ✅ Match iOS visual design
6. ✅ Save conversations locally

---

## 📋 Phase Breakdown

| Phase | Duration | Focus | Output |
|-------|----------|-------|--------|
| **Phase 1** | 3 days | SDK Integration & Model Management | Models download and load |
| **Phase 2** | 3 days | Text Generation & Analytics | Chat works with streaming |
| **Phase 3** | 2 days | UI/UX Parity with iOS | Looks identical to iOS |
| **Phase 4** | 2 days | Settings & Persistence | Data saved, settings work |
| **Total** | **10 days** | Fully functional app | Production-ready |

---

## Phase 1: SDK Integration & Model Management (3 days)

### Goal
Wire Android app to working Kotlin SDK for model operations.

### Day 1: SDK Initialization & Design System

#### 1.1 Add SDK Dependency (1 hour)

**File**: [app/build.gradle.kts](examples/android/RunAnywhereAI/app/build.gradle.kts)

```kotlin
dependencies {
    // RunAnywhere SDK (from Maven Local)
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
    implementation("com.runanywhere.sdk:runanywhere-llm-llamacpp-jvm:0.1.0")

    // Existing dependencies...
    implementation(libs.androidx.core.ktx)
    // ...
}
```

**Build SDK first:**
```bash
cd sdk/runanywhere-kotlin
./scripts/sdk.sh build
./scripts/sdk.sh publish
```

---

#### 1.2 Initialize SDK in Application (2 hours)

**File**: `app/src/main/java/com/runanywhere/runanywhereai/RunAnywhereApplication.kt`

```kotlin
package com.runanywhere.runanywhereai

import android.app.Application
import com.runanywhere.sdk.RunAnywhere
import com.runanywhere.sdk.SDKEnvironment
import com.runanywhere.sdk.modules.llamacpp.LlamaCppModule
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber

class RunAnywhereApplication : Application() {

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onCreate() {
        super.onCreate()

        // Initialize logging
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }

        // Initialize SDK
        initializeSDK()
    }

    private fun initializeSDK() {
        applicationScope.launch {
            try {
                Timber.d("🚀 Initializing RunAnywhere SDK...")

                // Step 1: Register LlamaCpp module
                LlamaCppModule.register()

                // Step 2: Initialize SDK (simple 3-line init)
                RunAnywhere.initialize(
                    apiKey = BuildConfig.RUNANYWHERE_API_KEY,
                    baseURL = BuildConfig.RUNANYWHERE_BASE_URL,
                    environment = if (BuildConfig.DEBUG) {
                        SDKEnvironment.DEVELOPMENT
                    } else {
                        SDKEnvironment.PRODUCTION
                    }
                )

                Timber.d("✅ SDK initialized successfully")
                Timber.d("📱 Device registered: ${RunAnywhere.isDeviceRegistered()}")

            } catch (e: Exception) {
                Timber.e(e, "❌ SDK initialization failed")
            }
        }
    }
}
```

**Update AndroidManifest.xml:**
```xml
<application
    android:name=".RunAnywhereApplication"
    android:allowBackup="true"
    ...>
```

**Add to build.gradle.kts (for API keys):**
```kotlin
android {
    defaultConfig {
        buildConfigField("String", "RUNANYWHERE_API_KEY", "\"${project.findProperty("RUNANYWHERE_API_KEY") ?: "test-key"}\"")
        buildConfigField("String", "RUNANYWHERE_BASE_URL", "\"${project.findProperty("RUNANYWHERE_BASE_URL") ?: "https://api.runanywhere.com"}\"")
    }
}
```

---

#### 1.3 Create iOS-Matching Design System (2 hours)

**File**: `app/src/main/java/com/runanywhere/runanywhereai/ui/theme/AppColors.kt`

```kotlin
package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.ui.graphics.Color

object AppColors {
    // iOS System Colors (exact hex values)
    val primaryBlue = Color(0xFF007AFF)
    val primaryGreen = Color(0xFF34C759)
    val primaryRed = Color(0xFFFF3B30)
    val primaryOrange = Color(0xFFFF9500)
    val primaryYellow = Color(0xFFFFCC00)

    // Text Colors (iOS)
    val textPrimary = Color(0xFF000000)
    val textSecondary = Color(0xFF3C3C43).copy(alpha = 0.6f)
    val textTertiary = Color(0xFF3C3C43).copy(alpha = 0.3f)

    // Backgrounds (Light)
    val backgroundPrimary = Color(0xFFFFFFFF)
    val backgroundSecondary = Color(0xFFF2F2F7)
    val backgroundTertiary = Color(0xFFFFFFFF)

    // Backgrounds (Dark)
    val backgroundPrimaryDark = Color(0xFF000000)
    val backgroundSecondaryDark = Color(0xFF1C1C1E)
    val backgroundTertiaryDark = Color(0xFF2C2C2E)

    // Message Bubbles (Light)
    val messageBubbleUser = Color(0xFF007AFF)
    val messageBubbleAssistant = Color(0xFFE5E5EA)

    // Message Bubbles (Dark)
    val messageBubbleUserDark = Color(0xFF0A84FF)
    val messageBubbleAssistantDark = Color(0xFF3A3A3C)

    // Framework Badges
    val badgeBlue = Color(0xFF007AFF).copy(alpha = 0.2f)
    val badgeGreen = Color(0xFF34C759).copy(alpha = 0.2f)
    val badgePurple = Color(0xFFAF52DE).copy(alpha = 0.2f)
    val badgeOrange = Color(0xFFFF9500).copy(alpha = 0.2f)

    // Shadows
    val shadowLight = Color.Black.copy(alpha = 0.1f)
    val shadowMedium = Color.Black.copy(alpha = 0.2f)
}
```

**File**: `app/src/main/java/com/runanywhere/runanywhereai/ui/theme/AppSpacing.kt`

```kotlin
package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.ui.unit.dp

object AppSpacing {
    // Base scale (matching iOS exactly)
    val xxSmall = 2.dp
    val xSmall = 4.dp
    val small = 8.dp
    val smallMedium = 10.dp
    val medium = 12.dp
    val large = 16.dp
    val xLarge = 20.dp
    val xxLarge = 24.dp
    val xxxLarge = 32.dp
    val huge = 40.dp

    // Corner Radius
    val cornerRadiusSmall = 8.dp
    val cornerRadiusMedium = 12.dp
    val cornerRadiusLarge = 16.dp
    val cornerRadiusXLarge = 20.dp

    // Layout
    val maxContentWidth = 700.dp
    val messageBubbleMaxWidth = 280.dp

    // Component Sizes
    val buttonHeight = 44.dp
    val micButtonSize = 80.dp
    val modelBadgeHeight = 32.dp
    val progressBarHeight = 4.dp

    // Animation Durations (ms)
    const val animationFast = 200
    const val animationNormal = 300
    const val animationSlow = 400
}
```

**Deliverable**: SDK initialized, design system matching iOS

---

### Day 2-3: Wire Model Management to SDK

See full implementation in document sections 2.1-2.2 (ModelsViewModel, ModelsScreen with SDK integration)

**Deliverable**: Models screen fully functional with SDK integration

---

## Phase 2: Text Generation & Analytics (3 days)

### Day 4-6: Wire Chat to SDK with Streaming & Analytics

See full implementation in document sections 4.1-4.2 (ChatViewModel with real SDK calls, ChatScreen with analytics display, markdown rendering)

**Deliverable**: Chat screen with real streaming generation and analytics display

---

## Phase 3: UI/UX Parity with iOS (2 days)

### Day 7-8: Polish UI to Match iOS Exactly

- Update typography to iOS specifications
- Add empty states
- Add animations
- Side-by-side comparison with iOS

**Deliverable**: App looks identical to iOS

---

## Phase 4: Settings & Persistence (2 days)

### Day 9-10: Add Data Persistence and Settings

- Room database for conversations
- DataStore for settings
- Settings screen matching iOS

**Deliverable**: Complete app with all features working

---

## ✅ Final Checklist

### SDK Integration
- [ ] SDK initialized in Application class
- [ ] LlamaCpp module registered
- [ ] Models can be downloaded
- [ ] Models can be loaded/unloaded
- [ ] Current model is tracked

### Text Generation
- [ ] Chat sends real prompts to SDK
- [ ] Streaming works (tokens appear one by one)
- [ ] Analytics are calculated and displayed
- [ ] Thinking content is parsed and shown
- [ ] Markdown is rendered

### UI/UX
- [ ] Colors match iOS exactly
- [ ] Spacing matches iOS
- [ ] Typography matches iOS
- [ ] Animations feel smooth
- [ ] Empty states are polished

### Data Persistence
- [ ] Conversations are saved to Room
- [ ] Conversations can be loaded
- [ ] Settings are persisted

### Settings
- [ ] Temperature slider works
- [ ] Max tokens works
- [ ] Settings affect generation

---

## Success Metrics

### Functional
```
✅ User can download a model
✅ User can load a model
✅ User can chat with the model
✅ Responses stream in real-time
✅ Analytics are accurate
✅ Conversations are saved
✅ Settings affect behavior
```

### Visual
```
✅ App looks identical to iOS
✅ Colors match exactly
✅ Spacing is pixel-perfect
✅ Animations are smooth
```

### Performance
```
✅ Streaming latency < 50ms per token
✅ UI is responsive during generation
✅ No dropped frames
```

---

## DEFERRED (not in this plan)
- Quiz screen integration
- Voice features (STT/TTS)
- Cloud routing
- Advanced analytics export
- Storage management screen

---

## References

- [iOS Implementation Details](examples/ios/RunAnywhereAI/IOS_IMPLEMENTATION_DETAILS.md)
- [Swift Text-to-Text Spec](examples/ios/RunAnywhereAI/SWIFT_TEXT_TO_TEXT_IMPLEMENTATION.md)
- [Kotlin SDK Implementation Plan](sdk/runanywhere-kotlin/docs/TEXT_TO_TEXT_IMPLEMENTATION_PLAN.md)
- [iOS Sample App Docs](examples/ios/RunAnywhereAI/IOS_SAMPLE_APP_DOCUMENTATION.md)
- [Android Sample App Docs](examples/android/RunAnywhereAI/ANDROID_SAMPLE_APP_DOCUMENTATION.md)

---

**Ready to start? Begin with Phase 1, Day 1! 🚀**

For complete code examples of each phase, refer to the original detailed plan above.
