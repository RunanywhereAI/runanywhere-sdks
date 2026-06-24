package com.runanywhere.sdk.runanywhereainpu

import android.app.Application
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Initializes the RunAnywhere SDK (Phase 1 synchronous; service bring-up runs in
 * the background). Engine registration + NPU probe happen in [AppViewModel] once
 * a coroutine scope is available.
 */
class RunAnywhereApp : Application() {
    override fun onCreate() {
        super.onCreate()
        RunAnywhere.initialize(context = this)
    }
}
