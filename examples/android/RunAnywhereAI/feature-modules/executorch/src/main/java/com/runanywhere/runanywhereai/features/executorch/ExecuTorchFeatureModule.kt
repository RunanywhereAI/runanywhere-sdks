package com.runanywhere.runanywhereai.features.executorch

import android.content.Context
import com.runanywhere.runanywhereai.llm.LLMService
import com.runanywhere.runanywhereai.llm.frameworks.ExecuTorchService
import com.runanywhere.runanywhereai.features.llamacpp.FeatureRequirements
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Named
import javax.inject.Singleton

/**
 * Dynamic feature module for ExecuTorch framework
 */
@Module
@InstallIn(SingletonComponent::class)
object ExecuTorchFeatureModule {
    
    @Provides
    @Singleton
    @Named("executorch")
    fun provideExecuTorchService(@ApplicationContext context: Context): LLMService {
        return ExecuTorchService(context)
    }
}

/**
 * Feature entry point for ExecuTorch
 */
class ExecuTorchFeature {
    companion object {
        const val FEATURE_NAME = "executorch"
        const val MIN_SDK_VERSION = 26 // Android 8.0+ for better native performance
        const val REQUIRED_MEMORY_MB = 1536 // 1.5GB minimum
        
        fun isSupported(context: Context): Boolean {
            // Check for GPU/DSP support
            val packageManager = context.packageManager
            val hasVulkan = packageManager.hasSystemFeature("android.hardware.vulkan.level")
            val hasGPU = packageManager.hasSystemFeature("android.hardware.opengles.aep")
            
            val memoryInfo = android.app.ActivityManager.MemoryInfo()
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            activityManager.getMemoryInfo(memoryInfo)
            
            val availableMemoryMB = memoryInfo.totalMem / (1024 * 1024)
            return availableMemoryMB >= REQUIRED_MEMORY_MB && (hasVulkan || hasGPU)
        }
        
        fun getRequirements(): FeatureRequirements {
            return FeatureRequirements(
                minSdkVersion = MIN_SDK_VERSION,
                requiredMemoryMB = REQUIRED_MEMORY_MB,
                requiredStorageMB = 300, // 300MB for models
                requiredFeatures = listOf(
                    "android.hardware.opengles.aep",
                    // "android.hardware.vulkan.level" // Optional for GPU acceleration
                ),
                supportedAbis = listOf("arm64-v8a", "armeabi-v7a"),
                description = "PyTorch ExecuTorch inference engine with GPU acceleration"
            )
        }
        
        fun getSupportedBackends(context: Context): List<String> {
            val backends = mutableListOf<String>()
            
            backends.add("XNNPACK") // Always available
            
            val packageManager = context.packageManager
            if (packageManager.hasSystemFeature("android.hardware.vulkan.level")) {
                backends.add("Vulkan")
            }
            if (packageManager.hasSystemFeature("android.hardware.opengles.aep")) {
                backends.add("OpenGL")
            }
            
            // Check for Qualcomm Hexagon DSP
            if (isQualcommDevice()) {
                backends.add("QNN") // Qualcomm Neural Network SDK
            }
            
            return backends
        }
        
        private fun isQualcommDevice(): Boolean {
            val manufacturer = android.os.Build.MANUFACTURER.lowercase()
            val model = android.os.Build.MODEL.lowercase()
            return manufacturer.contains("qualcomm") || 
                   model.contains("snapdragon") ||
                   android.os.Build.HARDWARE.lowercase().contains("qcom")
        }
    }
}