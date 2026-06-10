package com.runanywhere.runanywhereai.ui.screens.benchmark

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.benchmark.BenchDeviceInfo
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkCategory
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkProgress
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkResult
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkRun
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkRunner
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkStatus
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkStore
import com.runanywhere.runanywhereai.util.RACLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

class BenchmarkViewModel(application: Application) : AndroidViewModel(application) {

    private val runner = BenchmarkRunner(application)

    val deviceInfo: BenchDeviceInfo = runner.deviceInfo()
    val selected = mutableStateListOf(BenchmarkCategory.LLM)

    var isRunning by mutableStateOf(false)
        private set
    var progress by mutableStateOf<BenchmarkProgress?>(null)
        private set

    private var job: Job? = null

    val history: List<BenchmarkRun> get() = BenchmarkStore.runs

    fun toggle(category: BenchmarkCategory) {
        if (isRunning) return
        if (category in selected) selected.remove(category) else selected.add(category)
    }

    fun run() {
        if (isRunning || selected.isEmpty()) return
        val categories = selected.toSet()
        val startedAt = System.currentTimeMillis()
        val device = runner.deviceInfo()
        val results = mutableListOf<BenchmarkResult>()
        isRunning = true
        progress = null
        job = viewModelScope.launch(Dispatchers.Default) {
            var status = BenchmarkStatus.COMPLETED
            try {
                runner.run(
                    categories = categories,
                    onProgress = { progress = it },
                    onResult = { results += it },
                )
            } catch (e: CancellationException) {
                status = BenchmarkStatus.CANCELLED
            } catch (e: Exception) {
                RACLog.e("benchmark run failed", e)
                status = BenchmarkStatus.FAILED
            } finally {
                withContext(NonCancellable) {
                    BenchmarkStore.save(
                        BenchmarkRun(
                            id = UUID.randomUUID().toString(),
                            startedAt = startedAt,
                            completedAt = System.currentTimeMillis(),
                            status = status,
                            device = device,
                            results = results.toList(),
                        ),
                    )
                }
                isRunning = false
                progress = null
            }
        }
    }

    fun cancel() {
        job?.cancel()
    }

    fun delete(id: String) {
        BenchmarkStore.delete(id)
    }
}
