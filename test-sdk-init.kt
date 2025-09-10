#!/usr/bin/env kotlin

@file:DependsOn("com.runanywhere.sdk:runanywhere-kotlin-jvm:0.1.0")
@file:DependsOn("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.data.models.SDKEnvironment
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    try {
        println("Initializing RunAnywhere SDK...")
        RunAnywhere.initialize(
            apiKey = "dev-api-key",
            baseURL = null,
            environment = SDKEnvironment.DEVELOPMENT
        )
        println("SDK initialized successfully!")
    } catch (e: Exception) {
        println("Error initializing SDK: ${e.message}")
        e.printStackTrace()
    }
}

main()
