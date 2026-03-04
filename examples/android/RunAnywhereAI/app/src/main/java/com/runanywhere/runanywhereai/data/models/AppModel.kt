package com.runanywhere.runanywhereai.data.models

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.extensions.ModelCompanionFile
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFileDescriptor

data class AppModel(
    val id: String,
    val name: String,
    val url: String,
    val framework: InferenceFramework,
    val category: ModelCategory = ModelCategory.LANGUAGE,
    val memoryRequirement: Long = 0,
    val supportsLoraAdapters: Boolean = false,
    val companionFiles: List<ModelCompanionFile> = emptyList(),
    val files: List<ModelFileDescriptor> = emptyList(),
)
