package com.runanywhere.runanywhereai.navigation

import kotlinx.serialization.Serializable

// All app routes — type-safe via @Serializable
sealed interface Route {

    // Bottom nav tabs
    @Serializable data object Chat : Route
    @Serializable data object Vision : Route
    @Serializable data object Voice : Route
    @Serializable data object More : Route
    @Serializable data object Settings : Route

    // Secondary screens
    @Serializable data object Vlm : Route
    @Serializable data object Stt : Route
    @Serializable data object Tts : Route
    @Serializable data object Rag : Route
    @Serializable data object LoraManager : Route
    @Serializable data object Benchmarks : Route
    @Serializable data class BenchmarkDetail(val runId: String) : Route
}
