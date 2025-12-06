package com.runanywhere.reactnative

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.module.annotations.ReactModule

/**
 * RunAnywhere React Native Module (Minimal Stub for C++ TurboModule)
 *
 * This is a minimal Kotlin stub that only exists for module registration.
 * All business logic is implemented in the pure C++ TurboModule at:
 * - cpp/RunAnywhereModule.cpp
 * - android/src/main/cpp/react-native-runanywhere.cpp (JNI adapter)
 *
 * This class serves THREE purposes only:
 * 1. Load the native library containing the C++ TurboModule
 * 2. Register the module name with React Native
 * 3. Provide metadata for React Native's module system
 *
 * IMPORTANT: Do NOT add any method implementations here.
 * All functionality is handled by the C++ TurboModule via JSI.
 */
@ReactModule(name = RunAnywhereModule.NAME)
class RunAnywhereModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    companion object {
        const val NAME = "RunAnywhere"

        init {
            try {
                // Load the native library containing our C++ TurboModule
                // This triggers JNI_OnLoad in react-native-runanywhere.cpp
                // which registers the C++ TurboModule provider
                System.loadLibrary("runanywhere-react-native")
            } catch (e: UnsatisfiedLinkError) {
                // Library not found - this is expected during development
                // The C++ TurboModule will still work if the library is loaded elsewhere
                android.util.Log.w(NAME, "Native library not loaded: ${e.message}")
            }
        }
    }

    /**
     * Returns the module name for React Native registration.
     * Must match the name in NativeRunAnywhere.ts spec.
     */
    override fun getName(): String = NAME

    // =============================================================================
    // NOTE: No method implementations needed here!
    // =============================================================================
    //
    // All methods (createBackend, initialize, loadSTTModel, etc.) are implemented
    // in the C++ TurboModule and called directly from JavaScript via JSI.
    //
    // React Native's TurboModule system automatically routes calls to the C++
    // implementation when the New Architecture is enabled.
    //
    // This Kotlin class is ONLY used for:
    // - Module registration in the legacy architecture
    // - Loading the native library
    // - Providing module metadata
    //
    // =============================================================================
}
