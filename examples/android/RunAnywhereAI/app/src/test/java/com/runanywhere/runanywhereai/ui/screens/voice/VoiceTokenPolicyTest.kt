package com.runanywhere.runanywhereai.ui.screens.voice

import ai.runanywhere.proto.v1.TokenKind
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceTokenPolicyTest {
    @Test
    fun `only answer-compatible tokens are displayable`() {
        assertTrue(TokenKind.TOKEN_KIND_ANSWER.isDisplayableVoiceAnswer())
        // Older engines did not type tokens; preserve their answer output.
        assertTrue(TokenKind.TOKEN_KIND_UNSPECIFIED.isDisplayableVoiceAnswer())

        assertFalse(TokenKind.TOKEN_KIND_THOUGHT.isDisplayableVoiceAnswer())
        assertFalse(TokenKind.TOKEN_KIND_TOOL_CALL.isDisplayableVoiceAnswer())
    }
}
