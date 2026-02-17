package com.margelo.nitro.runanywhere.rag

import android.util.Log
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider

class RunAnywhereRAGPackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider { HashMap() }
    }

    companion object {
        private const val TAG = "RunAnywhereRAGPackage"
        
        init {
            try {
                Log.i(TAG, "Loading native library: runanywhererag...")
                runanywhereragOnLoad.initializeNative()
                Log.i(TAG, "Successfully loaded native library: runanywhererag")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load native library for RAG", e)
                throw e
            }
        }
    }
}
