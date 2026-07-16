package com.runanywhere.runanywhereai.ui.screens.benchmark

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.runanywhere.runanywhereai.R
import com.runanywhere.runanywhereai.data.benchmark.BenchmarkRun
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

// RunAnywhere brand palette for the share card (kept local so the card renders the
// same regardless of the app's active Material color scheme).
private val CardBackgroundTop = Color(0xFF1A0E06)
private val CardBackgroundBottom = Color(0xFF0B0B0C)
private val BrandOrange = Color(0xFFFF5500)
private val CardTextPrimary = Color(0xFFF5F3F1)
private val CardTextSecondary = Color(0xFF9A938E)
private val CardRowBackground = Color(0x14FFFFFF)

private const val SHARE_MIME = "image/png"

// The branded, shareable benchmark result card. Fixed 9:16 (Stories-friendly) so the
// captured PNG drops cleanly into Instagram / X without awkward cropping.
@Composable
fun BenchmarkShareCard(data: ShareCardData, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .aspectRatio(9f / 16f)
            .clip(RoundedCornerShape(24.dp))
            .background(Brush.verticalGradient(listOf(CardBackgroundTop, CardBackgroundBottom)))
            .padding(horizontal = 26.dp, vertical = 30.dp),
    ) {
        // Header — logo + wordmark + the modality this card covers.
        Row(verticalAlignment = Alignment.CenterVertically) {
            Image(
                painter = painterResource(R.drawable.runanywhere_logo),
                contentDescription = null,
                modifier = Modifier.size(40.dp),
            )
            Spacer(Modifier.width(10.dp))
            Text("RunAnywhere", color = CardTextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(6.dp))
        Text(
            data.modalityLabel,
            color = BrandOrange,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 2.sp,
        )

        Spacer(Modifier.height(24.dp))

        // Hero — the single headline number, kept to a readable size.
        data.hero?.let { hero ->
            Row(verticalAlignment = Alignment.Bottom) {
                Text(hero.value, color = BrandOrange, fontSize = 48.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(8.dp))
                Text(
                    hero.label,
                    color = CardTextSecondary,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
            }
            if (data.heroCaption.isNotBlank()) {
                Spacer(Modifier.height(4.dp))
                Text(
                    data.heroCaption,
                    color = CardTextPrimary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            data.heroSecondary?.let { secondary ->
                Text(
                    "${secondary.value} ${secondary.label}",
                    color = CardTextSecondary,
                    fontSize = 12.sp,
                )
            }
        }

        // Additional models only — the hero model is never repeated here.
        if (data.rows.isNotEmpty()) {
            Spacer(Modifier.height(24.dp))
            Text(
                "ALSO TESTED",
                color = CardTextSecondary,
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 1.5.sp,
            )
            Spacer(Modifier.height(8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                data.rows.forEach { row -> ShareRow(row) }
            }
        }

        // Footer pinned to the bottom.
        Spacer(Modifier.weight(1f))
        Text(data.deviceLine, color = CardTextPrimary, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(4.dp))
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("runanywhere.ai", color = BrandOrange, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Text(data.dateLine, color = CardTextSecondary, fontSize = 12.sp)
        }
    }
}

@Composable
private fun ShareRow(row: ShareCardRow) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(CardRowBackground)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(row.model, color = CardTextPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(row.framework, color = CardTextSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        row.metrics.forEach { metric ->
            Column(horizontalAlignment = Alignment.End, modifier = Modifier.padding(start = 16.dp)) {
                Text(metric.value, color = CardTextPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Text(metric.label, color = CardTextSecondary, fontSize = 11.sp)
            }
        }
    }
}

// Bottom sheet that previews the card and shares it as a PNG. The preview card itself
// is the capture source (rendered into a GraphicsLayer), so what the user sees is
// exactly what gets shared.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenchmarkShareSheet(run: BenchmarkRun, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // A run can span several modalities; each gets its own clean card so a single
    // image never has to cram LLM + STT + TTS + VLM together.
    val modalities = remember(run.id) { ShareCardData.availableModalities(run) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        if (modalities.isEmpty()) {
            Text(
                "No successful benchmarks to share yet. Run a benchmark first.",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 40.dp),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            return@ModalBottomSheet
        }

        var selected by remember(run.id) { mutableStateOf(modalities.first()) }
        val data = remember(run.id, selected) { ShareCardData.from(run, selected) }
        val graphicsLayer = rememberGraphicsLayer()

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Modality selector — only shown when there is more than one to choose from.
            if (modalities.size > 1) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    modalities.forEach { category ->
                        FilterChip(
                            selected = category == selected,
                            onClick = { selected = category },
                            label = { Text(category.name) },
                        )
                    }
                }
            }

            Box(
                modifier = Modifier.drawWithContent {
                    graphicsLayer.record { this@drawWithContent.drawContent() }
                    drawLayer(graphicsLayer)
                },
            ) {
                BenchmarkShareCard(data, modifier = Modifier.width(300.dp))
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                ShareTargetButton("Instagram", Modifier.weight(1f)) {
                    captureThen(scope, context, graphicsLayer) { uri -> shareToInstagramStory(context, uri, data.shareMessage) }
                }
                ShareTargetButton("X", Modifier.weight(1f)) {
                    captureThen(scope, context, graphicsLayer) { uri -> shareToX(context, uri, data.shareMessage) }
                }
                ShareTargetButton("More", Modifier.weight(1f)) {
                    captureThen(scope, context, graphicsLayer) { uri -> shareViaChooser(context, uri, data.shareMessage) }
                }
            }
        }
    }
}

@Composable
private fun ShareTargetButton(label: String, modifier: Modifier, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, modifier = modifier) {
        Text(label, style = MaterialTheme.typography.labelLarge)
    }
}

// Captures the on-screen card to a PNG in cache and hands its content URI to [then].
private fun captureThen(
    scope: CoroutineScope,
    context: Context,
    graphicsLayer: androidx.compose.ui.graphics.layer.GraphicsLayer,
    then: (Uri) -> Unit,
) {
    scope.launch {
        val bitmap = graphicsLayer.toImageBitmap().asAndroidBitmap()
        val uri = saveShareImage(context, bitmap)
        then(uri)
    }
}

private suspend fun saveShareImage(context: Context, bitmap: Bitmap): Uri = withContext(Dispatchers.IO) {
    val dir = File(context.cacheDir, "share").apply { mkdirs() }
    val file = File(dir, "runanywhere_benchmark.png")
    FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
}

private fun shareToInstagramStory(context: Context, uri: Uri, caption: String) {
    val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
        setDataAndType(uri, SHARE_MIME)
        putExtra("source_application", context.packageName)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        setPackage("com.instagram.android")
    }
    context.grantUriPermission("com.instagram.android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    launchOrFallback(context, intent, uri, caption, "Instagram not installed — opening share sheet")
}

private fun shareToX(context: Context, uri: Uri, caption: String) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = SHARE_MIME
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_TEXT, caption)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        setPackage("com.twitter.android")
    }
    launchOrFallback(context, intent, uri, caption, "X not installed — opening share sheet")
}

private fun shareViaChooser(context: Context, uri: Uri, caption: String) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = SHARE_MIME
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_TEXT, caption)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Share benchmark"))
}

// Tries a package-targeted share; falls back to the generic chooser if that app is
// absent so the user is never left with a dead button.
private fun launchOrFallback(context: Context, intent: Intent, uri: Uri, caption: String, fallbackNote: String) {
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        Toast.makeText(context, fallbackNote, Toast.LENGTH_SHORT).show()
        shareViaChooser(context, uri, caption)
    }
}
