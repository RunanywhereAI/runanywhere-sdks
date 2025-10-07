package com.runanywhere.ai.models.data

enum class ModelState {
    NOT_AVAILABLE,      // No download URL available
    AVAILABLE,          // Can be downloaded
    DOWNLOADING,        // Currently downloading
    DOWNLOADED,         // Downloaded but not loaded
    LOADING,           // Being loaded into memory
    LOADED,            // Loaded and ready to use
    BUILT_IN          // System-provided model
}
