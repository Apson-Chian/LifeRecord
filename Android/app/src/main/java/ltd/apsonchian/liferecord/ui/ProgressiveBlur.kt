package ltd.apsonchian.liferecord.ui

import android.app.ActivityManager
import android.content.Context
import android.graphics.RenderEffect as AndroidRenderEffect
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.ceil

@Composable
internal fun rememberBackdropBlurEnabled(): Boolean {
    val context = LocalContext.current
    val saving = rememberPowerSaveMode()
    return !saving && remember(context) {
        Build.VERSION.SDK_INT >= 31 &&
            !(context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice
    }
}

/** A non-interactive scroll edge sampling only glassSource. Labels never enter the blur. */
@Composable
fun ProgressiveBackdrop(
    backdrop: GlassBackdrop,
    modifier: Modifier = Modifier,
    maxBlurRadius: Dp = 24.dp,
    blurEnabled: Boolean = rememberBackdropBlurEnabled(),
) {
    require(maxBlurRadius.value.isFinite() && maxBlurRadius.value in 0f..48f)
    val colors = androidx.compose.material3.MaterialTheme.colorScheme
    val enabled = blurEnabled && Build.VERSION.SDK_INT >= 31 && maxBlurRadius > 0.dp
    Box(modifier.clipToBounds()) {
        if (Build.VERSION.SDK_INT >= 31 && enabled) {
            // System Gaussian filters are optimized by Skia. Blend actual radii instead
            // of nesting variable-radius shader samplers (expensive on mobile GPUs).
            listOf(.22f, .55f, 1f).forEachIndexed { index, fraction ->
                BackdropLayer(backdrop, Modifier.fillMaxSize(), maxBlurRadius * fraction) { size, padding, radius ->
                    ProgressiveBlurEffects.band(size, padding, radius, index)
                }
            }
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
            0f to colors.background.copy(alpha = 0f),
            .35f to colors.background.copy(alpha = if (enabled) .02f else .12f),
            .75f to colors.background.copy(alpha = if (enabled) .18f else .65f),
            1f to colors.background.copy(alpha = if (enabled) .46f else .94f),
        )))
    }
}

/** Filter an expanded source, then crop, avoiding clamped rows at the scroll edge. */
@Composable
internal fun BackdropLayer(
    backdrop: GlassBackdrop,
    modifier: Modifier,
    radius: Dp,
    effect: (Size, Float, Float) -> RenderEffect,
) {
    var origin by remember { mutableStateOf(Offset.Zero) }
    var dimensions by remember { mutableStateOf(IntSize.Zero) }
    // A quarter-resolution input is sufficient for frosted backgrounds. Foreground
    // content stays at full resolution, while each filter handles one sixteenth as many pixels.
    val inputScale = .25f
    val density = LocalDensity.current.density * inputScale
    val padding = ceil(radius.value * density * 3f).toInt()
    val layer = rememberGraphicsLayer()
    val background = androidx.compose.material3.MaterialTheme.colorScheme.background
    val renderEffect = remember(dimensions, density, radius, effect) {
        if (dimensions.width > 0 && dimensions.height > 0) {
            effect(Size(dimensions.width * inputScale, dimensions.height * inputScale), padding.toFloat(), radius.value * density)
        } else null
    }
    Box(modifier.onGloballyPositioned {
        origin = it.positionInRoot()
        dimensions = it.size
    }.drawWithContent {
        if (renderEffect != null) {
            layer.clip = true
            layer.renderEffect = renderEffect
            layer.record(size = IntSize(ceil(dimensions.width * inputScale).toInt() + padding * 2, ceil(dimensions.height * inputScale).toInt() + padding * 2)) {
                // Samples outside the page must remain opaque, otherwise the blurred
                // output reveals the sharp original near the physical screen edges.
                drawRect(background)
                val offset = origin - backdrop.origin
                scale(inputScale,inputScale,pivot=Offset.Zero) {
                    translate(padding / inputScale - offset.x, padding / inputScale - offset.y) { drawLayer(backdrop.layer) }
                }
            }
            scale(1f / inputScale,1f / inputScale,pivot=Offset.Zero) {
                translate(-padding.toFloat(), -padding.toFloat()) { drawLayer(layer) }
            }
        }
    })
}

@RequiresApi(31)
internal object ProgressiveBlurEffects {
    fun uniform(radius: Float): RenderEffect = AndroidRenderEffect.createBlurEffect(
        radius, radius, Shader.TileMode.CLAMP,
    ).asComposeRenderEffect()

    fun band(size: Size, padding: Float, radius: Float, index: Int): RenderEffect {
        val start = listOf(0f, .20f, .45f)[index]
        val end = listOf(.36f, .66f, 1f)[index]
        val mask = android.graphics.LinearGradient(
            0f, padding + size.height * start, 0f, padding + size.height * end,
            intArrayOf(0x00000000, 0x28000000, 0x80000000.toInt(), 0xD7000000.toInt(), 0xFF000000.toInt()),
            floatArrayOf(0f, .25f, .5f, .75f, 1f), Shader.TileMode.CLAMP,
        )
        return AndroidRenderEffect.createBlendModeEffect(
            AndroidRenderEffect.createBlurEffect(radius, radius, Shader.TileMode.CLAMP),
            AndroidRenderEffect.createShaderEffect(mask), android.graphics.BlendMode.DST_IN,
        ).asComposeRenderEffect()
    }

}
