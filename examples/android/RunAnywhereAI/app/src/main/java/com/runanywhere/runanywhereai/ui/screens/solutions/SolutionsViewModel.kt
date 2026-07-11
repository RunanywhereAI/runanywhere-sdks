package com.runanywhere.runanywhereai.ui.screens.solutions

import ai.runanywhere.proto.v1.ModelListRequest
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.SolutionHandle
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.solutions
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.cancellation.CancellationException

// Mirrors iOS SolutionsView.runSolution: create a handle from YAML, start(),
// then destroy() immediately — the demo only exercises the solution lifecycle.
// Each state transition is appended to a scrolling log.
class SolutionsViewModel : ViewModel() {

    val log = mutableStateListOf<String>()

    var isRunning by mutableStateOf(false)
        private set
    private var resolvedSolutions by mutableStateOf(AndroidSolutionsConfig.resolve(emptyList()))

    val missingVoiceModels: List<String> get() = resolvedSolutions.voice.missingModels
    val missingRagModels: List<String> get() = resolvedSolutions.rag.missingModels
    var isCheckingModels by mutableStateOf(true)
        private set

    val voiceReady: Boolean get() = resolvedSolutions.voice.isReady
    val ragReady: Boolean get() = resolvedSolutions.rag.isReady

    init {
        refreshRequirements()
    }

    fun refreshRequirements() {
        viewModelScope.launch {
            isCheckingModels = true
            val models = runCatching {
                RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
            }.getOrDefault(emptyList<RAModelInfo>())
            resolvedSolutions = AndroidSolutionsConfig.resolve(models)
            isCheckingModels = false
        }
    }

    fun runVoiceSolution() = runSolution("Voice Agent", resolvedSolutions.voice)

    fun runRagSolution() = runSolution("RAG", resolvedSolutions.rag)

    private fun runSolution(name: String, solution: ResolvedAndroidSolution) {
        if (isRunning) return
        val yaml = solution.yaml?.takeIf { solution.isReady } ?: return
        isRunning = true
        log.add("→ $name: creating solution from YAML…")
        viewModelScope.launch {
            var handle: SolutionHandle? = null
            try {
                handle = RunAnywhere.solutions.run(yaml)
                log.add("✓ $name: handle created. Calling start()…")
                handle.start()
                log.add("✓ $name: started. Tearing down (demo).")
                handle.destroy()
                log.add("✓ $name: destroyed.")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                log.add("✗ $name: ${e.message ?: e.toString()}")
            } finally {
                // Swift relies on the handle's deinit for the error path; with no
                // deterministic deinit on the JVM, destroy explicitly so leaving
                // the screen mid-run can't leak the native handle.
                withContext(NonCancellable) {
                    handle?.takeIf { it.isAlive }?.destroy()
                }
                isRunning = false
            }
        }
    }
}
