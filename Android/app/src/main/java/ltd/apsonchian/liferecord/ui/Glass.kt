package ltd.apsonchian.liferecord.ui

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

/** Capture only the page below the chrome, never the glass itself (no feedback loop). */
@Stable
class GlassBackdrop(val layer: GraphicsLayer) {
    var origin by mutableStateOf(Offset.Zero)
}

fun Modifier.glassSource(backdrop: GlassBackdrop): Modifier =
    onGloballyPositioned { backdrop.origin = it.positionInRoot() }.drawWithContent {
        backdrop.layer.record { this@drawWithContent.drawContent() }
        drawLayer(backdrop.layer)
    }

@Composable
fun AppBackground(modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    Canvas(modifier.fillMaxSize()) {
        drawRect(colors.background)
        drawRect(Brush.verticalGradient(listOf(colors.background, lerp(if(colors.background.luminance()<.2f) Color.Black else Color.White,colors.primary,.075f), colors.background)))
    }
}

/** Real source-backed blur on API 31; AGSL edge refraction on API 33. */
@Composable
fun GlassSurface(backdrop: GlassBackdrop, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val colors = MaterialTheme.colorScheme
    val dark = colors.background.luminance() < .2f
    val context = LocalContext.current
    val lowRam = remember(context) { (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var dimensions by remember { mutableStateOf(Size.Zero) }
    val density = LocalDensity.current.density
    val effect = remember(dimensions, density, lowRam) {
        if (Build.VERSION.SDK_INT >= 31 && !lowRam && dimensions.width > 0) {
            GlassEffects.blur(dimensions, density)
        } else null
    }
    val shape = RoundedCornerShape(50)
    Box(modifier
        .onGloballyPositioned { origin = it.positionInRoot(); dimensions = Size(it.size.width.toFloat(), it.size.height.toFloat()) }
        .shadow(12.dp, shape, ambientColor = Color.Black.copy(alpha = .08f), spotColor = Color.Black.copy(alpha = .12f))
        .clip(shape)
        .border(.8.dp, Brush.linearGradient(listOf(Color.White.copy(alpha = if(dark) .30f else .85f), colors.primary.copy(alpha = .08f), Color.White.copy(alpha = .20f))), shape)
    ) {
        if(effect != null) {
            Box(Modifier.matchParentSize().graphicsLayer { renderEffect = effect }.drawWithContent {
                val offset = origin - backdrop.origin
                translate(-offset.x, -offset.y) { drawLayer(backdrop.layer) }
            })
        }
        Box(Modifier.matchParentSize().background(colors.surface.copy(alpha = if(effect == null) .97f else if(dark) .64f else .57f)))
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.White.copy(alpha = if(dark) .06f else .16f), Color.Transparent, colors.primary.copy(alpha = .025f)))))
        content()
    }
}

@RequiresApi(31)
private object GlassEffects {
    fun blur(size: Size, density: Float): RenderEffect {
        val blur = android.graphics.RenderEffect.createBlurEffect(12f * density, 12f * density, android.graphics.Shader.TileMode.CLAMP)
        val effect = if(Build.VERSION.SDK_INT >= 33) runCatching { Refraction.effect(size, density, blur) }.getOrDefault(blur) else blur
        return effect.asComposeRenderEffect()
    }
}

@RequiresApi(33)
private object Refraction {
    // Rounded-rectangle distance field: refraction is localized to the perimeter.
    private const val SOURCE = """
        uniform shader backdrop;
        uniform float2 extent;
        uniform float radius;
        uniform float rim;
        half4 main(float2 p) {
            float2 center = extent * 0.5;
            float2 q = abs(p - center) - (center - radius);
            float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
            float edge = 1.0 - smoothstep(0.0, rim, -distance);
            float2 normal = normalize((p - center) / max(center, float2(1.0)) + float2(0.001));
            float2 samplePoint = clamp(p - normal * edge * rim * 0.32, float2(0.5), extent - 0.5);
            half4 color = backdrop.eval(samplePoint);
            return color;
        }
    """
    fun effect(size: Size, density: Float, blur: android.graphics.RenderEffect): android.graphics.RenderEffect {
        val shader = android.graphics.RuntimeShader(SOURCE).apply {
            setFloatUniform("extent", size.width, size.height)
            setFloatUniform("radius", size.height / 2)
            setFloatUniform("rim", 11f * density)
        }
        return android.graphics.RenderEffect.createChainEffect(android.graphics.RenderEffect.createRuntimeShaderEffect(shader, "backdrop"), blur)
    }
}

@Composable fun glassBarHeight(): Dp = if(LocalDensity.current.fontScale > 1.3f) 82.dp else 60.dp
@Composable fun glassPageBottomPadding(): Dp {
    val density = LocalDensity.current
    return glassBarHeight() + 36.dp + with(density) { WindowInsets.navigationBars.getBottom(this).toDp() }
}

@Composable
fun GlassNavigationBar(backdrop: GlassBackdrop, selected: Int, select: (Int) -> Unit, modifier: Modifier = Modifier) {
    val labels = listOf("今日", "趋势", "教练", "设置")
    val colors = MaterialTheme.colorScheme
    val height = glassBarHeight()
    var dragPosition by remember { mutableStateOf<Float?>(null) }
    BoxWithConstraints(modifier.widthIn(max = 500.dp).fillMaxWidth()) {
        val tabWidth = (maxWidth - 12.dp) / 4
        val widthPx = with(LocalDensity.current) { tabWidth.toPx() }
        val settledPosition by animateDpAsState(tabWidth * selected.toFloat(), spring(dampingRatio = 1f, stiffness = 700f), label = "glass selection")
        val position = dragPosition?.let { tabWidth * it } ?: settledPosition
        val choose = rememberUpdatedState(select)
        GlassSurface(backdrop, Modifier.fillMaxWidth().height(height).testTag("glass-navigation")
            .pointerInput(widthPx) {
                detectHorizontalDragGestures(
                    onDragStart = { dragPosition = ((it.x - 6.dp.toPx()) / widthPx - .5f).coerceIn(0f, 3f) },
                    onHorizontalDrag = { change, amount -> change.consume(); dragPosition = ((dragPosition ?: selected.toFloat()) + amount / widthPx).coerceIn(0f, 3f) },
                    onDragEnd = { dragPosition?.roundToInt()?.let { choose.value(it) }; dragPosition = null },
                    onDragCancel = { dragPosition = null }
                )
            }) {
            Box(Modifier.padding(6.dp).offset(x = position).width(tabWidth).fillMaxHeight()
                .clip(RoundedCornerShape(50)).background(colors.onSurface.copy(alpha = .055f))
                .border(.6.dp, Color.White.copy(alpha = if(colors.background.luminance()<.2f) .12f else .34f), RoundedCornerShape(50)))
            Row(Modifier.fillMaxSize().padding(6.dp).selectableGroup()) {
                labels.forEachIndexed { index, label ->
                    val interactions = remember { MutableInteractionSource() }
                    val pressed by interactions.collectIsPressedAsState()
                    val scale by animateFloatAsState(if(pressed) .94f else 1f, spring(stiffness = 900f), label = "tab press")
                    val color = if(selected == index) colors.primary else colors.onSurface
                    Column(Modifier.weight(1f).fillMaxHeight().testTag("tab-$index").clip(RoundedCornerShape(50))
                        .selectable(selected == index, interactionSource = interactions, indication = null, role = Role.Tab, onClick = { select(index) })
                        .graphicsLayer { scaleX = scale; scaleY = scale },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center
                    ) {
                        AppIcon(listOf(Glyph.Home,Glyph.Trend,Glyph.Coach,Glyph.Settings)[index],color,Modifier.size(24.dp),filled=index!=1)
                        Spacer(Modifier.height(3.dp))
                        Text(label, fontSize = 11.sp, fontWeight = if(selected == index) FontWeight.SemiBold else FontWeight.Medium, color = color, maxLines = 1)
                    }
                }
            }
        }
    }
}
