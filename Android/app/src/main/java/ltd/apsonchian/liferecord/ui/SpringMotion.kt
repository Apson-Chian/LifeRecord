package ltd.apsonchian.liferecord.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import kotlin.math.abs

/** Keep the existing native spring speeds; bounce only after a moving gesture. */
internal object SpringMotion {
    fun press() = spring<Float>(dampingRatio = 1f, stiffness = 850f)
    fun selection() = spring<Float>(dampingRatio = 1f, stiffness = 700f)
    fun release() = spring<Float>(dampingRatio = .8f, stiffness = 380f)

    // Apple's exponential momentum projection with the snappier .99 decay rate.
    fun projected(position: Float, velocity: Float) = position + velocity / 1000f * .99f / (1f - .99f)
    fun resisted(position: Float, min: Float, max: Float, dimension: Float): Float {
        val edge = position.coerceIn(min, max)
        val over = position - edge
        return edge + over * dimension * .55f / (dimension + .55f * abs(over))
    }
}

@Composable internal fun Modifier.springPress(source: MutableInteractionSource, enabled: Boolean = true, pressedScale: Float = .98f): Modifier {
    val pressed by source.collectIsPressedAsState()
    val motion = rememberMotionEnabled()
    val scale by animateFloatAsState(if (pressed && enabled && motion) pressedScale else 1f,
        if (motion) SpringMotion.press() else snap(), label = "press feedback")
    return graphicsLayer { scaleX = scale; scaleY = scale }
}

@Composable internal fun Modifier.springClickable(enabled: Boolean = true, role: Role? = null, onClick: () -> Unit): Modifier {
    val source = remember { MutableInteractionSource() }
    return springPress(source, enabled).clickable(enabled = enabled, interactionSource = source, indication = LocalIndication.current, role = role, onClick = onClick)
}
