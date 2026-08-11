plugins {
    id("com.android.application") version "9.2.1" apply false
    // AGP 9 supplies Kotlin itself (applying `kotlin.android` is now an error),
    // but its bundled compiler is 2.2.0 while the SDK is built with 2.4.0.
    // Putting a 2.4.0 Kotlin compiler plugin on the buildscript classpath pins
    // the built-in Kotlin to 2.4.0 — the same trick sdk/runanywhere-kotlin and
    // examples/android/RunAnywhereAI use. Without it the app fails with
    // "Module was compiled with an incompatible version of Kotlin".
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.0" apply false
}
