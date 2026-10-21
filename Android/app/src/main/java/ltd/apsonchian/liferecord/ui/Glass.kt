package ltd.apsonchian.liferecord.ui

import android.os.Build
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
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
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
    }
}

/** Quiet frosted material over the scroll edge; keep labels on a sharp layer. */
@Composable
fun GlassSurface(backdrop: GlassBackdrop, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val colors = MaterialTheme.colorScheme
    val dark = colors.background.luminance() < .2f
    val blurEnabled = rememberBackdropBlurEnabled()
    val shape = RoundedCornerShape(50)
    Box(modifier
        .shadow(8.dp, shape, ambientColor = Color.Black.copy(alpha = .05f), spotColor = Color.Black.copy(alpha = .08f))
        .clip(shape)
        .border(.5.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = if(dark) .16f else .55f), colors.outlineVariant.copy(alpha = .16f))), shape)
    ) {
        if (blurEnabled && Build.VERSION.SDK_INT >= 31) {
            BackdropLayer(backdrop, Modifier.matchParentSize(), 18.dp) { _, _, radius ->
                ProgressiveBlurEffects.uniform(radius)
            }
        }
        Box(Modifier.matchParentSize().background(colors.surface.copy(alpha = if (!blurEnabled) .97f else if (dark) .58f else .38f)))
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.White.copy(alpha = if (dark) .025f else .08f), Color.Transparent))))
        content()
    }
}

@Composable fun glassBarHeight(): Dp = if(LocalDensity.current.fontScale > 1.3f) 82.dp else 68.dp
@Composable fun glassPageBottomPadding(): Dp {
    val density = LocalDensity.current
    return glassBarHeight() + 36.dp + with(density) { WindowInsets.navigationBars.getBottom(this).toDp() }
}

@Composable
fun GlassNavigationBar(backdrop: GlassBackdrop, selected: Int, select: (Int) -> Unit, modifier: Modifier = Modifier) {
    val labels = listOf("今日", "趋势", "教练", "设置")
    val colors = MaterialTheme.colorScheme
    val height = glassBarHeight()
    val motion = rememberMotionEnabled()
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
                .clip(RoundedCornerShape(50)).background(colors.primary.copy(alpha = .12f))
                .border(.6.dp, Color.White.copy(alpha = if(colors.background.luminance()<.2f) .12f else .34f), RoundedCornerShape(50)))
            Row(Modifier.fillMaxSize().padding(6.dp).selectableGroup()) {
                labels.forEachIndexed { index, label ->
                    val interactions = remember { MutableInteractionSource() }
                    val pressed by interactions.collectIsPressedAsState()
                    val scale by animateFloatAsState(if(pressed && motion) .94f else 1f, spring(stiffness = 900f), label = "tab press")
                    val color = if(selected == index) colors.primary else colors.onSurfaceVariant
                    Column(Modifier.weight(1f).fillMaxHeight().testTag("tab-$index").clip(RoundedCornerShape(50))
                        .selectable(selected == index, interactionSource = interactions, indication = null, role = Role.Tab, onClick = { select(index) })
                        .graphicsLayer { scaleX = scale; scaleY = scale },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center
                    ) {
                        AppIcon(listOf(Glyph.Home,Glyph.Trend,Glyph.Coach,Glyph.Settings)[index],color,Modifier.size(24.dp),filled=selected==index && index!=1)
                        Spacer(Modifier.height(3.dp))
                        Text(label, fontSize = 11.sp, fontWeight = if(selected == index) FontWeight.SemiBold else FontWeight.Medium, color = color, maxLines = 1)
                    }
                }
            }
        }
    }
}
