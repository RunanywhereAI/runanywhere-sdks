package com.runanywhere.sdk.public.extensions.Models

import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelLoadResult
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ModelLifecycleArtifactResolutionTest {
    @Test
    fun `model load result resolves primary and projector by generated role`() {
        val result =
            ModelLoadResult(
                resolved_path = "/ignored/single-path.gguf",
                resolved_artifacts =
                    listOf(
                        ModelFileDescriptor(
                            role = ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
                            local_path = "/models/vlm/model.gguf",
                        ),
                        ModelFileDescriptor(
                            role = ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
                            local_path = "/models/vlm/mmproj.gguf",
                        ),
                    ),
            )

        assertEquals("/models/vlm/model.gguf", result.resolvedPrimaryModelPath())
        assertEquals("/models/vlm/mmproj.gguf", result.resolvedVisionProjectorPath())
    }

    @Test
    fun `current model result resolves projector from current lifecycle artifacts`() {
        val result =
            CurrentModelResult(
                model_id = "vlm",
                found = true,
                resolved_artifacts =
                    listOf(
                        ModelFileDescriptor(
                            role = ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
                            local_path = "/models/vlm/projector.gguf",
                        ),
                    ),
            )

        assertEquals("/models/vlm/projector.gguf", result.resolvedVisionProjectorPath())
    }

    @Test
    fun `lifecycle projector resolution does not fall back to generic companions`() {
        val result =
            ModelLoadResult(
                resolved_artifacts =
                    listOf(
                        ModelFileDescriptor(
                            role = ModelFileRole.MODEL_FILE_ROLE_COMPANION,
                            local_path = "/models/vlm/sidecar.gguf",
                        ),
                    ),
            )

        assertNull(result.resolvedVisionProjectorPath())
    }
}
