package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelArtifactType
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelSource
import com.runanywhere.sdk.public.RunAnywhere
import kotlin.coroutines.Continuation
import kotlin.test.Test
import kotlin.test.assertNotNull

class StorageRegistrationBinaryCompatibilityTest {
    private val owner = Class.forName("com.runanywhere.sdk.public.extensions.RunAnywhereStorageKt")

    @Test
    fun `retains URL registration JVM entry points`() {
        assertLegacyEntryPoints(
            String::class.java,
            String::class.java,
            String::class.java,
            InferenceFramework::class.java,
            ModelCategory::class.java,
            ModelArtifactType::class.java,
            Long::class.javaObjectType,
            Boolean::class.javaPrimitiveType!!,
            Boolean::class.javaPrimitiveType!!,
            Long::class.javaObjectType,
            String::class.java,
        )
    }

    @Test
    fun `retains archive registration JVM entry points`() {
        assertLegacyEntryPoints(
            String::class.java,
            ArchiveStructure::class.java,
            String::class.java,
            String::class.java,
            InferenceFramework::class.java,
            ModelCategory::class.java,
            ArchiveType::class.java,
            Long::class.javaObjectType,
            Boolean::class.javaPrimitiveType!!,
            Boolean::class.javaPrimitiveType!!,
            String::class.java,
        )
    }

    @Test
    fun `retains multi-file registration JVM entry points`() {
        assertLegacyEntryPoints(
            List::class.java,
            String::class.java,
            String::class.java,
            InferenceFramework::class.java,
            ModelCategory::class.java,
            Long::class.javaObjectType,
            Int::class.javaObjectType,
            Boolean::class.javaPrimitiveType!!,
            ModelSource::class.java,
            Long::class.javaObjectType,
            String::class.java,
        )
    }

    private fun assertLegacyEntryPoints(vararg parameters: Class<*>) {
        val signature = arrayOf(RunAnywhere::class.java, *parameters, Continuation::class.java)
        assertNotNull(owner.getDeclaredMethod("registerModel", *signature))
        assertNotNull(
            owner.getDeclaredMethod(
                "registerModel\$default",
                *signature,
                Int::class.javaPrimitiveType!!,
                Any::class.java,
            ),
        )
    }
}
