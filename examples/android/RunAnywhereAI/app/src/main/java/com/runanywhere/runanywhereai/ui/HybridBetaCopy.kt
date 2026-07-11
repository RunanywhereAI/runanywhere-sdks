package com.runanywhere.runanywhereai.ui

/** Consumer-facing copy for the optional Hybrid transcription preview. */
internal object HybridBetaCopy {
    const val LABEL = "Hybrid (Beta)"
    const val MODE_EXPLANATION =
        "$LABEL tries the on-device model first and requires a configured cloud provider for fallback."
    const val CLOUD_PROVIDER_REQUIRED =
        "Add a cloud provider from Advanced before using $LABEL transcription."
    const val CLOUD_PROVIDER_PICKER_EMPTY =
        "Add a provider from Advanced > Cloud providers before using $LABEL transcription."
    const val TRANSCRIPTION_FAILED =
        "$LABEL transcription failed. Check the on-device model and cloud provider, then try again."
    const val CLOUD_PROVIDERS_EXPLANATION =
        "Register any cloud STT provider — its key, endpoint and format. " +
            "Registered providers can back the cloud side of $LABEL transcription."
    const val TRANSCRIPTION_ENTRY_DESCRIPTION =
        "Batch, live, and $LABEL speech recognition"
    const val CLOUD_PROVIDERS_ENTRY_DESCRIPTION =
        "Configure cloud speech backends for $LABEL"
}
