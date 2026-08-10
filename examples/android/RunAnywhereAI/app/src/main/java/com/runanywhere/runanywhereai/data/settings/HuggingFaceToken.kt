package com.runanywhere.runanywhereai.data.settings

import com.runanywhere.runanywhereai.data.ModelBootstrap
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import kotlin.coroutines.cancellation.CancellationException

/**
 * Storing a Hugging Face sign-in is three things that have to happen together — an encrypted
 * write, the SDK's live credential, and a catalog refresh so the gated rows appear — and each of
 * them can fail differently.
 *
 * It lives here rather than in whichever screen happens to own a text field because two surfaces
 * now ask for the token: Settings, and the model picker at the moment a private model is tapped.
 * Two copies of this sequence would drift, and the one that drifted would leave a token saved but
 * not applied.
 */
object HuggingFaceToken {

    val isPresent: Boolean get() = SettingsRepository.settings.hfToken.isNotBlank()

    /** What the caller has to tell the user. Nothing here names an internal component. */
    sealed interface Outcome {
        data object Saved : Outcome
        data object Cleared : Outcome

        /** Stored, but the running SDK did not pick it up; a restart applies it. */
        data object SavedNotApplied : Outcome
        data class Failed(val message: String) : Outcome
    }

    suspend fun save(raw: String): Outcome {
        val candidate = raw.trim()
        val clearing = candidate.isBlank()

        SettingsRepository.setHfToken(candidate).exceptionOrNull()?.let { failure ->
            RACLog.e("Hugging Face token secure-storage update failed", failure)
            return Outcome.Failed(
                if (clearing) {
                    "Could not securely clear the Hugging Face sign-in"
                } else {
                    "Could not securely save the Hugging Face sign-in"
                },
            )
        }

        return try {
            // Empty clears the token (public no-auth behavior); never logged.
            RunAnywhere.setHfToken(candidate)
            ModelBootstrap.refreshNpuCatalog()
            if (clearing) Outcome.Cleared else Outcome.Saved
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("Hugging Face token was saved but could not be applied", e)
            Outcome.SavedNotApplied
        }
    }
}
