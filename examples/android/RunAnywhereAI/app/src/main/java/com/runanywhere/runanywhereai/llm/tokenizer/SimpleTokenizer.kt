package com.runanywhere.runanywhereai.llm.tokenizer

/**
 * Simple space-based tokenizer for demonstration purposes
 *
 * This tokenizer splits text by spaces and assigns token IDs based on word frequency.
 * Not suitable for production use - real models require proper tokenization.
 */
class SimpleTokenizer : Tokenizer {
    private val vocabulary = mutableMapOf<String, Int>()
    private val reverseVocab = mutableMapOf<Int, String>()
    private val specialTokens = mapOf(
        "<pad>" to 0,
        "<unk>" to 1,
        "<s>" to 2,
        "</s>" to 3,
        "<mask>" to 4
    )

    init {
        // Initialize with special tokens
        specialTokens.forEach { (token, id) ->
            vocabulary[token] = id
            reverseVocab[id] = token
        }

        // Add some common words for demonstration
        val commonWords = listOf(
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "have", "has", "had", "do", "does", "did", "will", "would",
            "can", "could", "should", "may", "might", "must", "shall",
            "to", "of", "in", "for", "on", "at", "by", "with", "from",
            "up", "about", "into", "through", "during", "before", "after",
            "above", "below", "between", "under", "over", "out", "off",
            "I", "you", "he", "she", "it", "we", "they", "me", "him", "her",
            "and", "or", "but", "if", "then", "because", "as", "until",
            "what", "when", "where", "who", "which", "why", "how",
            "all", "some", "any", "none", "more", "most", "less", "least",
            "very", "quite", "just", "only", "even", "still", "also", "too"
        )

        commonWords.forEachIndexed { index, word ->
            val tokenId = specialTokens.size + index
            vocabulary[word.lowercase()] = tokenId
            reverseVocab[tokenId] = word
        }
    }

    override fun encode(text: String): List<Int> {
        // Simple whitespace tokenization
        val words = text.lowercase().split(Regex("\\s+"))
        return words.map { word ->
            vocabulary[word] ?: getUnkToken()
        }
    }

    override fun decode(tokens: List<Int>): String {
        return tokens.mapNotNull { tokenId ->
            reverseVocab[tokenId]
        }.joinToString(" ")
    }

    override fun vocabSize(): Int {
        return vocabulary.size
    }

    override fun getSpecialTokens(): Map<String, Int> {
        return specialTokens
    }
}
