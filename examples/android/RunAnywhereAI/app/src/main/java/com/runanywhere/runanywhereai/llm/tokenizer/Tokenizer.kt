package com.runanywhere.runanywhereai.llm.tokenizer

/**
 * Base interface for all tokenizer implementations
 * 
 * Tokenizers are responsible for converting text to tokens and vice versa.
 * Different models use different tokenization strategies (BPE, WordPiece, SentencePiece, etc.)
 */
interface Tokenizer {
    /**
     * Encode text into a list of token IDs
     */
    fun encode(text: String): List<Int>
    
    /**
     * Decode a list of token IDs back into text
     */
    fun decode(tokens: List<Int>): String
    
    /**
     * Get the vocabulary size
     */
    fun vocabSize(): Int
    
    /**
     * Get special tokens used by this tokenizer
     */
    fun getSpecialTokens(): Map<String, Int>
    
    /**
     * Get the padding token ID
     */
    fun getPadToken(): Int = getSpecialTokens()["<pad>"] ?: 0
    
    /**
     * Get the unknown token ID
     */
    fun getUnkToken(): Int = getSpecialTokens()["<unk>"] ?: 0
    
    /**
     * Get the beginning of sentence token ID
     */
    fun getBosToken(): Int? = getSpecialTokens()["<s>"]
    
    /**
     * Get the end of sentence token ID
     */
    fun getEosToken(): Int? = getSpecialTokens()["</s>"]
    
    /**
     * Encode text with special tokens (BOS/EOS)
     */
    fun encodeWithSpecialTokens(text: String): List<Int> {
        val tokens = mutableListOf<Int>()
        getBosToken()?.let { tokens.add(it) }
        tokens.addAll(encode(text))
        getEosToken()?.let { tokens.add(it) }
        return tokens
    }
    
    /**
     * Batch encode multiple texts
     */
    fun encodeBatch(texts: List<String>): List<List<Int>> {
        return texts.map { encode(it) }
    }
    
    /**
     * Batch decode multiple token sequences
     */
    fun decodeBatch(tokenBatch: List<List<Int>>): List<String> {
        return tokenBatch.map { decode(it) }
    }
}

/**
 * Factory for creating tokenizers based on model type
 */
object TokenizerFactory {
    /**
     * Create a tokenizer based on the model type and configuration
     */
    fun createTokenizer(type: TokenizerType, modelPath: String? = null): Tokenizer {
        return when (type) {
            TokenizerType.SIMPLE -> SimpleTokenizer()
            TokenizerType.BPE -> BPETokenizer(modelPath ?: throw IllegalArgumentException("BPE requires model path"))
            TokenizerType.SENTENCEPIECE -> SentencePieceTokenizer(modelPath ?: throw IllegalArgumentException("SentencePiece requires model path"))
            TokenizerType.WORDPIECE -> WordPieceTokenizer(modelPath ?: throw IllegalArgumentException("WordPiece requires vocab path"))
            TokenizerType.LLAMA -> LlamaTokenizer(modelPath ?: throw IllegalArgumentException("Llama tokenizer requires model path"))
        }
    }
}

/**
 * Supported tokenizer types
 */
enum class TokenizerType {
    SIMPLE,        // Basic space-based tokenization
    BPE,           // Byte Pair Encoding (GPT-2 style)
    SENTENCEPIECE, // SentencePiece (used by many models)
    WORDPIECE,     // WordPiece (BERT style)
    LLAMA          // Llama-specific tokenizer
}