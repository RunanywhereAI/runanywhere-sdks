package com.runanywhere.runanywhereai.features.llamacpp

import android.content.Context
import com.runanywhere.runanywhereai.llm.LLMService
import com.runanywhere.runanywhereai.llm.frameworks.LlamaCppService
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Named
import javax.inject.Singleton

/**
 * Dynamic feature module for llama.cpp framework
 */
@Module
@InstallIn(SingletonComponent::class)
object LlamaCppFeatureModule {
    
    @Provides
    @Singleton
    @Named("llamacpp")
    fun provideLlamaCppService(@ApplicationContext context: Context): LLMService {
        return LlamaCppService(context)
    }
}

/**
 * Feature entry point for llama.cpp
 */
class LlamaCppFeature {
    companion object {
        const val FEATURE_NAME = "llamacpp"
        const val MIN_SDK_VERSION = 24
        const val REQUIRED_MEMORY_MB = 2048 // 2GB minimum
        
        fun isSupported(context: Context): Boolean {
            val memoryInfo = android.app.ActivityManager.MemoryInfo()
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            activityManager.getMemoryInfo(memoryInfo)
            
            val availableMemoryMB = memoryInfo.totalMem / (1024 * 1024)
            return availableMemoryMB >= REQUIRED_MEMORY_MB
        }
        
        fun getRequirements(): FeatureRequirements {
            return FeatureRequirements(
                minSdkVersion = MIN_SDK_VERSION,
                requiredMemoryMB = REQUIRED_MEMORY_MB,
                requiredStorageMB = 500, // 500MB for models
                requiredFeatures = listOf("android.hardware.ram"),
                supportedAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64"),
                description = "Native llama.cpp inference engine for GGUF models"
            )
        }
    }
}

/**
 * Feature requirements data class
 */
data class FeatureRequirements(
    val minSdkVersion: Int,
    val requiredMemoryMB: Long,
    val requiredStorageMB: Long,
    val requiredFeatures: List<String>,
    val supportedAbis: List<String>,
    val description: String
)