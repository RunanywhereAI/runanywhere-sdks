package com.runanywhere.runanywhereai.ui.screens.intro

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.R
import com.runanywhere.runanywhereai.ui.components.rememberBreath
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens

/**
 * The app's own boot screen, shown between the platform launch window handing off
 * and the SDK reporting ready.
 *
 * This used to be a wordmark over a bare indeterminate bar, held for the whole
 * 14.1 s of SDK init *plus* catalog seeding. Catalog seeding now runs behind the
 * live app (see `RunAnywhereApplication.seedCatalogInBackground`), so the wait
 * here is the ~0.6 s of `RunAnywhere.initialize()` and this screen's job changed:
 * it is no longer a progress report, it is the brand moment that covers one
 * handoff. Hence a breathing mark and a line of plain-language copy rather than a
 * bar — a determinate-looking bar over half a second reads as a stutter, and an
 * indeterminate one invites the user to wonder how long it will run.
 *
 * It still has to look deliberate on a slow first launch (cold dex, cold disk),
 * so the mark's pulse is a slow continuous loop with no beginning or end to catch.
 */
@Composable
fun IntroScreen() {
    val dimens = LocalDimens.current

    // Fade the whole screen in rather than cutting to it. The launch window shows
    // the same mark on the same background, so an instant swap would visibly jump
    // the logo from the platform's mask position to ours.
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val entry by animateFloatAsState(
        targetValue = if (shown) 1f else 0f,
        animationSpec = AppMotion.emphasis(),
        label = "introEntry",
    )

    // The shared 1.6 s pulse period, not a bespoke 2.2 s one: this is the same "something
    // is working" breath the chat pips and the thinking glyph use, and three different
    // periods for one idea is how a motion system stops being a system. Returns its resting
    // value under reduced motion, so the halo is simply still.
    val pulse = rememberBreath(min = 0f, max = 1f, label = "introPulse")

    Box(
        modifier = Modifier
            .fillMaxSize()
            .systemBarsPadding()
            .alpha(entry),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(contentAlignment = Alignment.Center) {
                // A soft brand halo behind the mark. Scale and opacity ride the same
                // pulse in one `graphicsLayer`, so it is one compositor property set
                // per frame — and it reads as one glow breathing, not two animations.
                Box(
                    modifier = Modifier
                        .size(HALO_SIZE)
                        .graphicsLayer {
                            val s = HALO_SCALE_MIN + pulse * HALO_SCALE_RANGE
                            scaleX = s
                            scaleY = s
                            alpha = HALO_ALPHA_MIN + pulse * HALO_ALPHA_RANGE
                        }
                        .background(
                            brush = Brush.radialGradient(
                                listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.background),
                            ),
                            shape = CircleShape,
                        ),
                )
                Image(
                    painter = painterResource(R.drawable.runanywhere_logo),
                    contentDescription = "RunAnywhere",
                    modifier = Modifier
                        .size(MARK_SIZE)
                        // A narrower range than the halo: the mark should settle,
                        // not throb.
                        .graphicsLayer {
                            val s = MARK_SCALE_MIN + pulse * MARK_SCALE_RANGE
                            scaleX = s
                            scaleY = s
                        },
                )
            }

            Spacer(Modifier.height(dimens.spacingXl))

            Text(
                "RunAnywhere",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onBackground,
            )

            Spacer(Modifier.height(dimens.spacingSm))

            Text(
                // What the user gets, not what the process is doing. "Loading
                // model catalog…" named an implementation detail they can neither
                // act on nor care about.
                "Private AI, running on your device",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = dimens.spacingXl),
            )
        }
    }
}

@Composable
fun InitErrorScreen(message: String, onRetry: () -> Unit) {
    val dimens = LocalDimens.current
    Column(
        Modifier
            .fillMaxSize()
            .systemBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(dimens.spacingXl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Image(
            painter = painterResource(R.drawable.runanywhere_logo),
            contentDescription = null,
            modifier = Modifier
                .size(56.dp)
                .alpha(0.4f),
        )

        Spacer(Modifier.height(dimens.spacingXl))

        Text(
            // Says what the user can do, not what the subsystem is called.
            // "Initialization Failed" is a log line, not a message.
            "Couldn't start",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onBackground,
        )

        Spacer(Modifier.height(dimens.spacingSm))

        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = dimens.contentMaxWidth),
        )

        Spacer(Modifier.height(dimens.spacingXl))

        Button(onClick = onRetry) {
            Text("Try again")
        }
    }
}

// The boot mark's geometry. Named because a raw `0.92f + pulse * 0.16f` at a call site says
// nothing about which end is rest and which is the excursion.
private val HALO_SIZE = 160.dp
private const val HALO_SCALE_MIN = 0.92f
private const val HALO_SCALE_RANGE = 0.16f
private const val HALO_ALPHA_MIN = 0.10f
private const val HALO_ALPHA_RANGE = 0.14f

private val MARK_SIZE = 88.dp
private const val MARK_SCALE_MIN = 0.97f
private const val MARK_SCALE_RANGE = 0.06f
