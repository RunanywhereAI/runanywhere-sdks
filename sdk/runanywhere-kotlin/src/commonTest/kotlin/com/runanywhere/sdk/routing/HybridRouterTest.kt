package com.runanywhere.sdk.routing

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.public.extensions.STT.STTOptions
import com.runanywhere.sdk.public.extensions.STT.STTOutput
import com.runanywhere.sdk.public.extensions.STT.TranscriptionMetadata
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

// ─── Stub backends ────────────────────────────────────────────────────────────

private fun localBackend(
    moduleId: String = "whisper-local",
    basePriority: Int = 200,
    modelLoaded: Boolean = true,
): STTBackend = object : STTBackend {
    override fun descriptors() = listOf(
        BackendDescriptor(
            moduleId = moduleId,
            moduleName = "Local Stub",
            capability = SDKComponent.STT,
            inferenceFramework = InferenceFramework.ONNX,
            basePriority = basePriority,
            conditions = listOf(
                RoutingCondition.LocalOnly,
                RoutingCondition.ModelAvailability("whisper") { modelLoaded },
                RoutingCondition.CostModel(0f),
            ),
        )
    )

    override suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTOutput =
        stubOutput("local")
}

private fun cloudBackend(
    moduleId: String = "sarvam-cloud",
    basePriority: Int = 80,
    apiKeySet: Boolean = true,
): STTBackend = object : STTBackend {
    override fun descriptors() = listOf(
        BackendDescriptor(
            moduleId = moduleId,
            moduleName = "Cloud Stub",
            capability = SDKComponent.STT,
            inferenceFramework = InferenceFramework.SARVAM,
            basePriority = basePriority,
            conditions = listOf(
                RoutingCondition.NetworkRequired,
                RoutingCondition.QualityTier(BackendQuality.HIGH),
                RoutingCondition.CostModel(2.5f),
                RoutingCondition.Custom("api-key", check = { apiKeySet }),
            ),
        )
    )

    override suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTOutput =
        stubOutput("cloud")
}

private fun stubOutput(source: String) = STTOutput(
    text = "hello from $source",
    confidence = 0.9f,
    metadata = TranscriptionMetadata("stub", 0.1, 1.0),
)

private fun router(vararg backends: STTBackend): HybridRouter {
    val r = HybridRouter()
    backends.forEach { r.register(it) }
    return r
}

// ─── Tests ────────────────────────────────────────────────────────────────────

class HybridRouterTest {

    @Test
    fun localWinsByDefaultWhenBothAvailable() {
        val r = router(localBackend(), cloudBackend())
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.AUTO,
        )
        val candidates = r.resolve(SDKComponent.STT, context)
        assertEquals("whisper-local", candidates.first().moduleId)
    }

    @Test
    fun cloudExcludedWhenOffline() {
        val r = router(localBackend(), cloudBackend())
        val context = RoutingContext(
            isNetworkAvailable = false,
            routingPolicy = RoutingPolicy.AUTO,
        )
        val candidates = r.resolve(SDKComponent.STT, context)
        assertEquals(1, candidates.size)
        assertEquals("whisper-local", candidates.first().moduleId)
    }

    @Test
    fun localExcludedWhenModelNotLoaded() {
        val r = router(localBackend(modelLoaded = false), cloudBackend())
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.AUTO,
        )
        val candidates = r.resolve(SDKComponent.STT, context)
        assertEquals(1, candidates.size)
        assertEquals("sarvam-cloud", candidates.first().moduleId)
    }

    @Test
    fun emptyWhenBothExcluded() {
        // local model not loaded + offline → both excluded
        val r = router(localBackend(modelLoaded = false), cloudBackend())
        val context = RoutingContext(
            isNetworkAvailable = false,
            routingPolicy = RoutingPolicy.AUTO,
        )
        val candidates = r.resolve(SDKComponent.STT, context)
        assertTrue(candidates.isEmpty())
    }

    @Test
    fun preferLocalPolicyBoostsLocal() {
        val r = router(localBackend(), cloudBackend())
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.PREFER_LOCAL,
        )
        val candidates = r.resolve(SDKComponent.STT, context)
        assertEquals("whisper-local", candidates.first().moduleId)
    }

    @Test
    fun cloudOnlyPolicyExcludesLocal() {
        val r = router(localBackend(), cloudBackend())
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.CLOUD_ONLY,
        )
        val candidates = r.resolve(SDKComponent.STT, context)
        assertEquals(1, candidates.size)
        assertEquals("sarvam-cloud", candidates.first().moduleId)
    }

    @Test
    fun localOnlyPolicyExcludesCloud() {
        val r = router(localBackend(), cloudBackend())
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.LOCAL_ONLY,
        )
        val candidates = r.resolve(SDKComponent.STT, context)
        assertEquals(1, candidates.size)
        assertEquals("whisper-local", candidates.first().moduleId)
    }

    @Test
    fun preferredFrameworkOverridesDefaultOrder() {
        val r = router(localBackend(), cloudBackend())
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.AUTO,
            preferredFramework = InferenceFramework.SARVAM,
        )
        val candidates = r.resolve(SDKComponent.STT, context)
        assertEquals("sarvam-cloud", candidates.first().moduleId)
    }

    @Test
    fun cloudExcludedWhenApiKeyMissing() {
        val r = router(localBackend(), cloudBackend(apiKeySet = false))
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.AUTO,
        )
        val candidates = r.resolve(SDKComponent.STT, context)
        assertEquals(1, candidates.size)
        assertEquals("whisper-local", candidates.first().moduleId)
    }

    @Test
    fun noCandidatesWhenNoBackendsRegistered() {
        val r = HybridRouter()
        val context = RoutingContext(
            isNetworkAvailable = true,
            routingPolicy = RoutingPolicy.AUTO,
        )
        assertTrue(r.resolve(SDKComponent.STT, context).isEmpty())
    }
}
