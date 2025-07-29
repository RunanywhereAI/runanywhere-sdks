package com.runanywhere.runanywhereai.llm.tokenizer

import android.util.Log
import java.io.File

/**
 * WordPiece tokenizer implementation
 * 
 * Used by BERT and similar models. This is a placeholder implementation.
 * A real implementation would load vocab.txt and perform actual WordPiece tokenization.
 */
class WordPieceTokenizer(private val vocabPath: String) : Tokenizer {
    companion object {
        private const val TAG = "WordPieceTokenizer"
        private const val UNK_TOKEN = "[UNK]"
        private const val SEP_TOKEN = "[SEP]"
        private const val PAD_TOKEN = "[PAD]"
        private const val CLS_TOKEN = "[CLS]"
        private const val MASK_TOKEN = "[MASK]"
    }
    
    private val vocabFile = File(vocabPath)
    private val vocabulary = mutableMapOf<String, Int>()
    private val reverseVocab = mutableMapOf<Int, String>()
    
    private val specialTokens = mapOf(
        PAD_TOKEN to 0,
        UNK_TOKEN to 100,
        CLS_TOKEN to 101,
        SEP_TOKEN to 102,
        MASK_TOKEN to 103
    )
    
    init {
        // Initialize special tokens
        specialTokens.forEach { (token, id) ->
            vocabulary[token] = id
            reverseVocab[id] = token
        }
        
        if (vocabFile.exists()) {
            Log.d(TAG, "Loading WordPiece vocabulary from: $vocabPath")
            // loadVocabulary()
        } else {
            Log.w(TAG, "Vocabulary file not found, using placeholder tokenization")
            initializePlaceholderVocab()
        }
    }
    
    private fun initializePlaceholderVocab() {
        // Add basic tokens for demonstration
        val basicTokens = listOf(
            "##ing", "##ed", "##er", "##est", "##ly", "##tion", "##ment",
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "have", "has", "had", "do", "does", "did", "will", "would",
            "can", "could", "should", "may", "might", "must", "shall"
        )
        
        basicTokens.forEachIndexed { index, token ->
            val id = 104 + index // Start after special tokens
            vocabulary[token] = id
            reverseVocab[id] = token
        }
        
        // Add single characters
        for (i in 'a'..'z') {
            val token = i.toString()
            val id = vocabulary.size
            vocabulary[token] = id
            reverseVocab[id] = token
        }
    }
    
    override fun encode(text: String): List<Int> {
        // WordPiece tokenization process:
        // 1. Basic tokenization (split by whitespace and punctuation)
        // 2. For each word, try to match longest tokens from vocabulary
        // 3. If not found, split into subwords with ## prefix
        
        val tokens = mutableListOf<Int>()
        
        // Add CLS token at start
        tokens.add(vocabulary[CLS_TOKEN]!!)
        
        // Simple word splitting for demonstration
        val words = text.lowercase().split(Regex("\\s+"))
        
        for (word in words) {
            if (vocabulary.containsKey(word)) {
                tokens.add(vocabulary[word]!!)
            } else {
                // Try to split into subwords
                var remaining = word
                while (remaining.isNotEmpty()) {
                    var found = false
                    for (len in remaining.length downTo 1) {
                        val subword = if (tokens.isNotEmpty() && len < remaining.length) {
                            "##${remaining.substring(0, len)}"
                        } else {
                            remaining.substring(0, len)
                        }
                        
                        if (vocabulary.containsKey(subword)) {
                            tokens.add(vocabulary[subword]!!)
                            remaining = remaining.substring(len)
                            found = true
                            break
                        }
                    }
                    
                    if (!found) {
                        tokens.add(vocabulary[UNK_TOKEN]!!)
                        break
                    }
                }
            }
        }
        
        // Add SEP token at end
        tokens.add(vocabulary[SEP_TOKEN]!!)
        
        return tokens
    }
    
    override fun decode(tokens: List<Int>): String {
        val words = mutableListOf<String>()
        var currentWord = StringBuilder()
        
        for (tokenId in tokens) {
            val token = reverseVocab[tokenId] ?: continue
            
            // Skip special tokens
            if (token in specialTokens.keys) continue
            
            if (token.startsWith("##")) {
                // Continuation of previous word
                currentWord.append(token.substring(2))
            } else {
                // New word
                if (currentWord.isNotEmpty()) {
                    words.add(currentWord.toString())
                    currentWord = StringBuilder()
                }
                currentWord.append(token)
            }
        }
        
        if (currentWord.isNotEmpty()) {
            words.add(currentWord.toString())
        }
        
        return words.joinToString(" ")
    }
    
    override fun vocabSize(): Int = vocabulary.size
    
    override fun getSpecialTokens(): Map<String, Int> = specialTokens
    
    override fun getPadToken(): Int = specialTokens[PAD_TOKEN]!!
    
    override fun getUnkToken(): Int = specialTokens[UNK_TOKEN]!!
    
    override fun getBosToken(): Int = specialTokens[CLS_TOKEN]!!
    
    override fun getEosToken(): Int = specialTokens[SEP_TOKEN]!!
}