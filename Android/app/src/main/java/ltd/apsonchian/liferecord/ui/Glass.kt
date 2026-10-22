package ltd.apsonchian.liferecord.ui

import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
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
    var screenOrigin by mutableStateOf(Offset.Zero)
    var ownerView by mutableStateOf<android.view.View?>(null)
}

@Composable
fun Modifier.glassSource(backdrop: GlassBackdrop): Modifier {
    val view=LocalView.current
    DisposableEffect(backdrop,view) {
        backdrop.ownerView=view
        onDispose {if(backdrop.ownerView===view) backdrop.ownerView=null}
    }
    return onGloballyPositioned {backdrop.origin=it.positionInRoot();backdrop.screenOrigin=it.positionOnScreen()}.legacyBlurRedraw(force=true).drawWithContent {
        backdrop.layer.record {this@drawWithContent.drawContent()}
        drawLayer(backdrop.layer)
    }
}

@Composable
fun AppBackground(modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    val dark=colors.background.luminance()<.2f
    Canvas(modifier.fillMaxSize()) {
        drawRect(Brush.verticalGradient(listOf(colors.background,lerp(colors.background,colors.primary,if(dark) .035f else .035f),colors.background)))
        drawRect(Brush.radialGradient(listOf(colors.secondary.copy(alpha=if(dark) .14f else .12f),Color.Transparent),Offset(size.width*.03f,size.height*.10f),size.width*1.15f))
        drawRect(Brush.radialGradient(listOf(colors.primary.copy(alpha=if(dark) .12f else .08f),Color.Transparent),Offset(size.width*1.04f,size.height*.47f),size.width*.95f))
        drawRect(Brush.radialGradient(listOf(Color(0xFF8CCBC6).copy(alpha=if(dark) .05f else .065f),Color.Transparent),Offset(size.width*.10f,size.height*.93f),size.width))
    }
}

/** Floating clear glass; optical treatment never filters its labels. */
@Composable
fun GlassSurface(backdrop:GlassBackdrop,modifier:Modifier=Modifier,content:@Composable BoxScope.()->Unit) {
    Box(modifier.liquidMaterial(backdrop,GlassKind.Floating),content=content)
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
    val position = remember { Animatable(selected.toFloat()) }
    var dragging by remember { mutableStateOf(false) }
    var rawPosition by remember { mutableFloatStateOf(selected.toFloat()) }
    var settleRequest by remember { mutableIntStateOf(0) }
    var releaseVelocity by remember { mutableStateOf<Float?>(null) }
    LaunchedEffect(selected, motion, dragging, settleRequest) {
        if (!dragging) {
            val velocity = releaseVelocity
            releaseVelocity = null
            if (motion) position.animateTo(selected.toFloat(), if (velocity == null) SpringMotion.selection() else SpringMotion.release(), initialVelocity = velocity ?: position.velocity)
            else position.snapTo(selected.toFloat())
        }
    }
    BoxWithConstraints(modifier.widthIn(max = 500.dp).fillMaxWidth()) {
        val tabWidth = (maxWidth - 12.dp) / 4
        val widthPx = with(LocalDensity.current) { tabWidth.toPx() }
        fun presentedPosition() = if (dragging) SpringMotion.resisted(rawPosition, 0f, 3f, 1f) else position.value
        val choose = rememberUpdatedState(select)
        GlassSurface(backdrop, Modifier.fillMaxWidth().height(height).testTag("glass-navigation")
            .draggable(
                state = rememberDraggableState { delta -> rawPosition += delta / widthPx },
                orientation = Orientation.Horizontal,
                startDragImmediately = position.isRunning,
                onDragStarted = {
                    // Freeze the presentation value, preserving where the finger grabbed it.
                    position.stop()
                    rawPosition = position.value
                    dragging = true
                },
                onDragStopped = { velocity ->
                    val current = presentedPosition()
                    val normalized = velocity / widthPx
                    val target = SpringMotion.projected(current, normalized).roundToInt().coerceIn(0, 3)
                    position.snapTo(current)
                    releaseVelocity = if (motion) normalized else 0f
                    choose.value(target)
                    dragging = false
                    settleRequest++
                }
            )) {
            Box(Modifier.padding(6.dp).graphicsLayer { translationX = presentedPosition() * widthPx }.width(tabWidth).fillMaxHeight().testTag("glass-selection")
                .shadow(2.dp,RoundedCornerShape(50),ambientColor=Color.Black.copy(alpha=.035f),spotColor=Color.Black.copy(alpha=.07f))
                .clip(RoundedCornerShape(50)).background(colors.primary.copy(alpha=.11f))
                .liquidFinish(GlassKind.Control,RoundedCornerShape(50),colors.primary,colors.background.luminance()<.2f))
            Row(Modifier.fillMaxSize().padding(6.dp).selectableGroup()) {
                labels.forEachIndexed { index, label ->
                    val interactions = remember { MutableInteractionSource() }
                    val color = if(selected == index) colors.primary else colors.onSurfaceVariant
                    Column(Modifier.weight(1f).fillMaxHeight().testTag("tab-$index").clip(RoundedCornerShape(50))
                        .selectable(selected == index, interactionSource = interactions, indication = null, role = Role.Tab, onClick = { select(index) })
                        .springPress(interactions, pressedScale=.97f),
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
