package com.runanywhere.sdk.foundation

/**
 * JVM implementation of PlatformContext
 */
actual class PlatformContext(
    private val workingDirectory: String = System.getProperty("user.dir"),
) {
    actual fun initialize() {
        // JVM doesn't need special initialization
        // Working directory is already set
        System.setProperty("runanywhere.workdir", workingDirectory)
    }
}
