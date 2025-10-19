package com.runanywhere.runanywhereai

import com.runanywhere.runanywhereai.domain.models.Language
import com.runanywhere.runanywhereai.domain.models.VoiceSTTConfig
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Test
import org.junit.Assert.*

/**
 * Unit tests for the Language structured type
 */
class LanguageTypeTest {

    private val json = Json { prettyPrint = true }

    @Test
    fun `Language AUTO is correctly identified`() {
        val language = Language.AUTO
        assertEquals("auto", language.toString())
    }

    @Test
    fun `Language Locale validates correct format`() {
        // Valid formats
        val en = Language.Locale("en")
        assertEquals("en", en.toString())

        val enUs = Language.Locale("en-US")
        assertEquals("en-US", enUs.toString())
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Language Locale rejects blank code`() {
        Language.Locale("")
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Language Locale rejects invalid format`() {
        Language.Locale("invalid")
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Language Locale rejects uppercase language code`() {
        Language.Locale("EN")
    }

    @Test(expected = IllegalArgumentException::class)
    fun `Language Locale rejects lowercase country code`() {
        Language.Locale("en-us")
    }

    @Test
    fun `Language fromString converts correctly`() {
        assertEquals(Language.AUTO, Language.fromString("auto"))
        assertEquals(Language.AUTO, Language.fromString("AUTO"))
        assertEquals(Language.AUTO, Language.fromString(""))

        val en = Language.fromString("en")
        assertTrue(en is Language.Locale)
        assertEquals("en", (en as Language.Locale).code)

        val enUs = Language.fromString("en-US")
        assertTrue(enUs is Language.Locale)
        assertEquals("en-US", (enUs as Language.Locale).code)
    }

    @Test
    fun `VoiceSTTConfig uses Language type`() {
        val config1 = VoiceSTTConfig(
            modelId = "whisper-base",
            language = Language.AUTO,
            enableRealTime = true
        )
        assertEquals(Language.AUTO, config1.language)

        val config2 = VoiceSTTConfig(
            modelId = "whisper-base",
            language = Language.Locale.ENGLISH_US,
            enableRealTime = true
        )
        assertEquals("en-US", config2.language.toString())
    }

    @Test
    fun `VoiceSTTConfig prevents arbitrary string values`() {
        // This test demonstrates that you cannot use arbitrary strings
        // The following line would not compile:
        // val config = VoiceSTTConfig(modelId = "whisper-base", language = "arbitrary-value")

        // Instead, you must use the structured Language type:
        val validConfig = VoiceSTTConfig(
            modelId = "whisper-base",
            language = Language.Locale("es"),
            enableRealTime = true
        )
        assertEquals("es", validConfig.language.toString())
    }

    @Test
    fun `VoiceSTTConfig serialization works correctly`() {
        val config = VoiceSTTConfig(
            modelId = "whisper-base",
            language = Language.Locale.ENGLISH,
            enableRealTime = true
        )

        val jsonString = json.encodeToString(config)
        assertTrue(jsonString.contains("whisper-base"))
        assertTrue(jsonString.contains("en") || jsonString.contains("locale"))

        val deserialized = json.decodeFromString<VoiceSTTConfig>(jsonString)
        assertEquals(config.modelId, deserialized.modelId)
        assertEquals(config.language.toString(), deserialized.language.toString())
        assertEquals(config.enableRealTime, deserialized.enableRealTime)
    }

    @Test
    fun `Language predefined constants work correctly`() {
        assertEquals("en", Language.Locale.ENGLISH.code)
        assertEquals("en-US", Language.Locale.ENGLISH_US.code)
        assertEquals("es", Language.Locale.SPANISH.code)
        assertEquals("fr", Language.Locale.FRENCH.code)
        assertEquals("de", Language.Locale.GERMAN.code)
        assertEquals("zh", Language.Locale.CHINESE.code)
    }

    @Test
    fun `Objects with different languages are not equal`() {
        val config1 = VoiceSTTConfig(
            modelId = "whisper-base",
            language = Language.Locale.ENGLISH,
            enableRealTime = true
        )

        val config2 = VoiceSTTConfig(
            modelId = "whisper-base",
            language = Language.Locale.SPANISH,
            enableRealTime = true
        )

        val config3 = VoiceSTTConfig(
            modelId = "whisper-base",
            language = Language.AUTO,
            enableRealTime = true
        )

        assertNotEquals(config1, config2)
        assertNotEquals(config1, config3)
        assertNotEquals(config2, config3)
    }
}
