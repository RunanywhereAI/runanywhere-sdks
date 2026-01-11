package com.margelo.nitro.runanywhere

import android.util.Log
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider

class RunAnywhereCorePackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        // Initialize secure storage with application context
        SecureStorageManager.initialize(reactContext.applicationContext)
        return null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider { HashMap() }
    }

    companion object {
        private const val TAG = "RunAnywhereCorePackage"
        
        init {
            System.loadLibrary("runanywherecore")
            Log.i(TAG, "Loaded native library: runanywherecore")
        }
    }
}
