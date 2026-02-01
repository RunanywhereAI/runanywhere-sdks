/**
 * KokoroTokenizer - Converts text to phoneme tokens for Kokoro TTS
 *
 * Kokoro uses a phoneme-based tokenizer where:
 * 1. Text is converted to phonemes (IPA)
 * 2. Phonemes are mapped to token IDs using tokens.txt
 *
 * The tokens.txt file format:
 *   <phoneme> <id>
 *   ; 1
 *   : 2
 *   ...
 */
package com.runanywhere.sdk.core.onnx.tts

import android.util.Log
import java.io.File

/**
 * Tokenizer for Kokoro TTS model.
 */
class KokoroTokenizer private constructor(
    private val phonemeToId: Map<String, Int>,
    private val idToPhoneme: Map<Int, String>
) {
    companion object {
        private const val TAG = "KokoroTokenizer"
        
        // Special tokens
        private const val PAD_TOKEN = 0
        private const val UNK_TOKEN = 1
        private const val BOS_TOKEN = 2  // Beginning of sequence
        private const val EOS_TOKEN = 3  // End of sequence
        
        /**
         * Load tokenizer from tokens.txt file.
         */
        fun load(tokensPath: String): KokoroTokenizer {
            val phonemeToId = mutableMapOf<String, Int>()
            val idToPhoneme = mutableMapOf<Int, String>()
            
            File(tokensPath).readLines().forEach { line ->
                if (line.isBlank()) return@forEach
                
                // Format: "phoneme id" or "phoneme\tid"
                val parts = line.split(Regex("\\s+"), limit = 2)
                if (parts.size >= 2) {
                    val phoneme = parts[0]
                    val id = parts[1].trim().toIntOrNull() ?: return@forEach
                    phonemeToId[phoneme] = id
                    idToPhoneme[id] = phoneme
                }
            }
            
            Log.i(TAG, "Loaded ${phonemeToId.size} tokens from $tokensPath")
            return KokoroTokenizer(phonemeToId, idToPhoneme)
        }
    }
    
    /** Number of tokens in vocabulary */
    val vocabSize: Int get() = phonemeToId.size
    
    /**
     * Encode text to token IDs.
     *
     * For now, this does a simple character-level encoding.
     * For better quality, integrate espeak-ng for proper phoneme conversion.
     *
     * @param text Input text
     * @return List of token IDs
     */
    fun encode(text: String): List<Long> {
        val tokens = mutableListOf<Long>()
        
        // Add BOS token if available
        if (phonemeToId.containsKey("<bos>")) {
            tokens.add(phonemeToId["<bos>"]!!.toLong())
        }
        
        // Process text character by character
        // This is simplified - proper implementation would use espeak-ng for phonemes
        val normalizedText = normalizeText(text)
        
        for (char in normalizedText) {
            val charStr = char.toString()
            val id = phonemeToId[charStr]
                ?: phonemeToId[charStr.lowercase()]
                ?: phonemeToId[" "] // Space as fallback
                ?: UNK_TOKEN
            tokens.add(id.toLong())
        }
        
        // Add EOS token if available
        if (phonemeToId.containsKey("<eos>")) {
            tokens.add(phonemeToId["<eos>"]!!.toLong())
        }
        
        Log.d(TAG, "Encoded '${text.take(50)}...' to ${tokens.size} tokens")
        return tokens
    }
    
    /**
     * Encode phonemes directly (if phoneme string is provided).
     *
     * @param phonemes IPA phoneme string
     * @return List of token IDs
     */
    fun encodePhonemes(phonemes: String): List<Long> {
        val tokens = mutableListOf<Long>()
        
        // Split on whitespace and process each phoneme
        phonemes.split(Regex("\\s+")).forEach { phoneme ->
            if (phoneme.isBlank()) return@forEach
            val id = phonemeToId[phoneme] ?: UNK_TOKEN
            tokens.add(id.toLong())
        }
        
        return tokens
    }
    
    /**
     * Decode token IDs back to text/phonemes (for debugging).
     */
    fun decode(tokens: List<Long>): String {
        return tokens.mapNotNull { idToPhoneme[it.toInt()] }.joinToString("")
    }
    
    /**
     * Normalize text for tokenization.
     */
    private fun normalizeText(text: String): String {
        return text
            // Basic normalization
            .replace(Regex("\\s+"), " ")
            .trim()
            // Handle common contractions
            .replace("'", "'")
            // Handle punctuation spacing
            .replace(Regex("([.!?,;:])"), " $1 ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }
}
