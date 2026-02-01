/**
 * KokoroVoices - Voice/speaker management for Kokoro TTS
 *
 * Kokoro v1.0 has 53 voices with naming convention:
 *   - af_* : American Female (11 voices)
 *   - am_* : American Male (9 voices)
 *   - bf_* : British Female (4 voices)
 *   - bm_* : British Male (4 voices)
 *   - Plus additional voices
 *
 * The voice ID maps to speaker_id input tensor.
 */
package com.runanywhere.sdk.core.onnx.tts

import android.util.Log
import java.io.File

/**
 * Voice information.
 */
data class KokoroVoice(
    val id: String,
    val name: String,
    val language: String,
    val gender: String,
    val speakerId: Int
)

/**
 * Voice manager for Kokoro TTS.
 */
class KokoroVoices private constructor(
    private val voiceMap: Map<String, KokoroVoice>
) {
    companion object {
        private const val TAG = "KokoroVoices"
        
        // Default Kokoro v1.0 voices (53 total)
        private val DEFAULT_VOICES = listOf(
            // American Female
            KokoroVoice("af_alloy", "Alloy", "en-US", "female", 0),
            KokoroVoice("af_aoede", "Aoede", "en-US", "female", 1),
            KokoroVoice("af_bella", "Bella", "en-US", "female", 2),
            KokoroVoice("af_heart", "Heart", "en-US", "female", 3),
            KokoroVoice("af_jessica", "Jessica", "en-US", "female", 4),
            KokoroVoice("af_kore", "Kore", "en-US", "female", 5),
            KokoroVoice("af_nicole", "Nicole", "en-US", "female", 6),
            KokoroVoice("af_nova", "Nova", "en-US", "female", 7),
            KokoroVoice("af_river", "River", "en-US", "female", 8),
            KokoroVoice("af_sarah", "Sarah", "en-US", "female", 9),
            KokoroVoice("af_sky", "Sky", "en-US", "female", 10),
            
            // American Male
            KokoroVoice("am_adam", "Adam", "en-US", "male", 11),
            KokoroVoice("am_echo", "Echo", "en-US", "male", 12),
            KokoroVoice("am_eric", "Eric", "en-US", "male", 13),
            KokoroVoice("am_fenrir", "Fenrir", "en-US", "male", 14),
            KokoroVoice("am_liam", "Liam", "en-US", "male", 15),
            KokoroVoice("am_michael", "Michael", "en-US", "male", 16),
            KokoroVoice("am_onyx", "Onyx", "en-US", "male", 17),
            KokoroVoice("am_puck", "Puck", "en-US", "male", 18),
            KokoroVoice("am_santa", "Santa", "en-US", "male", 19),
            
            // British Female
            KokoroVoice("bf_alice", "Alice", "en-GB", "female", 20),
            KokoroVoice("bf_emma", "Emma", "en-GB", "female", 21),
            KokoroVoice("bf_isabella", "Isabella", "en-GB", "female", 22),
            KokoroVoice("bf_lily", "Lily", "en-GB", "female", 23),
            
            // British Male
            KokoroVoice("bm_daniel", "Daniel", "en-GB", "male", 24),
            KokoroVoice("bm_fable", "Fable", "en-GB", "male", 25),
            KokoroVoice("bm_george", "George", "en-GB", "male", 26),
            KokoroVoice("bm_lewis", "Lewis", "en-GB", "male", 27),
            
            // Additional voices (simplified list - full model has more)
            KokoroVoice("af_shimmer", "Shimmer", "en-US", "female", 28),
            KokoroVoice("am_sage", "Sage", "en-US", "male", 29),
        )
        
        /**
         * Load voices from voices.bin file.
         *
         * Note: The voices.bin file contains voice embeddings, not a list of voices.
         * We use the default voice list and the file is used by the model internally.
         */
        fun load(voicesPath: String): KokoroVoices {
            val file = File(voicesPath)
            if (!file.exists()) {
                Log.w(TAG, "Voices file not found: $voicesPath, using defaults")
                return default()
            }
            
            // The voices.bin is used by the model internally
            // We return the default voice list which matches the model
            Log.i(TAG, "Voices file found: ${file.length()} bytes")
            return default()
        }
        
        /**
         * Get default voice list.
         */
        fun default(): KokoroVoices {
            val voiceMap = DEFAULT_VOICES.associateBy { it.id }
            return KokoroVoices(voiceMap)
        }
    }
    
    /** Number of available voices */
    val count: Int get() = voiceMap.size
    
    /**
     * List all voice IDs.
     */
    fun list(): List<String> = voiceMap.keys.toList()
    
    /**
     * List all voices with details.
     */
    fun listVoices(): List<KokoroVoice> = voiceMap.values.toList()
    
    /**
     * Get speaker ID for a voice.
     *
     * @param voiceId Voice ID (e.g., "af_bella")
     * @return Speaker ID or null if not found
     */
    fun getId(voiceId: String): Int? {
        return voiceMap[voiceId]?.speakerId
            ?: voiceMap[voiceId.lowercase()]?.speakerId
    }
    
    /**
     * Get voice info.
     */
    fun getVoice(voiceId: String): KokoroVoice? {
        return voiceMap[voiceId] ?: voiceMap[voiceId.lowercase()]
    }
    
    /**
     * Filter voices by language.
     */
    fun byLanguage(language: String): List<KokoroVoice> {
        return voiceMap.values.filter { it.language.equals(language, ignoreCase = true) }
    }
    
    /**
     * Filter voices by gender.
     */
    fun byGender(gender: String): List<KokoroVoice> {
        return voiceMap.values.filter { it.gender.equals(gender, ignoreCase = true) }
    }
    
    /**
     * Get the default voice.
     */
    fun defaultVoice(): KokoroVoice = voiceMap["af_bella"] ?: voiceMap.values.first()
}
