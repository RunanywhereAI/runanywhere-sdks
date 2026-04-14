package com.runanywhere.sdk.routing

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumented tests for the HybridRouter running on a device/emulator.
 *
 * These tests verify routing behavior with real network checks and
 * the actual backend descriptors (without hitting cloud APIs or loading models).
 *
 * To run:
 *   ./gradlew :connectedAndroidTest
 */
@RunWith(AndroidJUnit4::class)
class STTRoutingInstrumentedTest {

    private lateinit var router: HybridRouter

    @Before
    fun setup() {
        // Use real context for NetworkConnectivity
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        // Initialize platform context so NetworkConnectivity works
        com.runanywhere.sdk.storage.AndroidPlatformContext.initialize(context)

        router = HybridRouter()
        router.register(stubLocalBackend(modelLoaded = true))
        router.register(stubCloudBackend(apiKeySet = true))
    }

    @Test
    fun localIsFirstCandidateUnderAutoPolicy() {
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.AUTO,
        )
        val candidates = router.resolve(SDKComponent.STT, context)
        assertTrue("Expected at least one candidate", candidates.isNotEmpty())
        assertEquals("whisper-local", candidates.first().moduleId)
    }

    @Test
    fun cloudOnlyPolicyYieldsCloudBackend() {
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.CLOUD_ONLY,
        )
        val candidates = router.resolve(SDKComponent.STT, context)
        assertTrue("Expected cloud candidate", candidates.isNotEmpty())
        assertTrue(candidates.all { it.requiresNetwork })
    }

    @Test
    fun localOnlyPolicyYieldsLocalBackend() {
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.LOCAL_ONLY,
        )
        val candidates = router.resolve(SDKComponent.STT, context)
        assertTrue("Expected local candidate", candidates.isNotEmpty())
        assertTrue(candidates.all { it.isLocalOnly })
    }

    @Test
    fun preferredFrameworkSarvamRoutesToCloud() {
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.AUTO,
            preferredFramework = InferenceFramework.SARVAM,
        )
        val candidates = router.resolve(SDKComponent.STT, context)
        assertTrue("Expected at least one candidate", candidates.isNotEmpty())
        assertEquals(InferenceFramework.SARVAM, candidates.first().inferenceFramework)
    }

    @Test
    fun offlineExcludesCloudBackend() {
        val context = RoutingContext(
            isNetworkAvailable = false,
            routingPolicy = RoutingPolicy.AUTO,
        )
        val candidates = router.resolve(SDKComponent.STT, context)
        assertTrue("Expected only local candidates when offline", candidates.none { it.requiresNetwork })
    }

    // ─── Stub helpers ─────────────────────────────────────────────────────────

    private fun stubLocalBackend(modelLoaded: Boolean) = object : STTBackend {
        override fun descriptors() = listOf(
            BackendDescriptor(
                moduleId = "whisper-local",
                moduleName = "Whisper (Local)",
                capability = SDKComponent.STT,
                inferenceFramework = InferenceFramework.ONNX,
                basePriority = 200,
                conditions = listOf(
                    RoutingCondition.LocalOnly,
                    RoutingCondition.ModelAvailability("whisper") { modelLoaded },
                    RoutingCondition.CostModel(0f),
                ),
            )
        )

        override suspend fun transcribe(
            audioData: ByteArray,
            options: com.runanywhere.sdk.public.extensions.STT.STTOptions,
        ) = error("Not called in routing tests")
    }

    private fun stubCloudBackend(apiKeySet: Boolean) = object : STTBackend {
        override fun descriptors() = listOf(
            BackendDescriptor(
                moduleId = "sarvam-cloud",
                moduleName = "Sarvam (Cloud)",
                capability = SDKComponent.STT,
                inferenceFramework = InferenceFramework.SARVAM,
                basePriority = 80,
                conditions = listOf(
                    RoutingCondition.NetworkRequired,
                    RoutingCondition.QualityTier(BackendQuality.HIGH),
                    RoutingCondition.CostModel(2.5f),
                    RoutingCondition.Custom("api-key", check = { apiKeySet }),
                ),
            )
        )

        override suspend fun transcribe(
            audioData: ByteArray,
            options: com.runanywhere.sdk.public.extensions.STT.STTOptions,
        ) = error("Not called in routing tests")
    }
}
