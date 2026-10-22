package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Match iOS CardSurface: grouped fill, diagonal tint, fine edge and quiet depth. */
@Composable
internal fun Modifier.cardMaterial(tint: Color = MaterialTheme.colorScheme.primary, radius: Dp = 26.dp): Modifier {
    val dark = MaterialTheme.colorScheme.background.luminance() < .2f
    val shape = RoundedCornerShape(radius)
    return this
        .shadow(if (dark) 0.dp else 14.dp, shape, clip = false,
            ambientColor = tint.copy(alpha = .045f), spotColor = tint.copy(alpha = .045f))
        .shadow(if (dark) 0.dp else 2.dp, shape, clip = false,
            ambientColor = Color.Black.copy(alpha = .025f), spotColor = Color.Black.copy(alpha = .025f))
        .clip(shape)
        .background(MaterialTheme.colorScheme.surface)
        .background(Brush.linearGradient(listOf(tint.copy(alpha = if (dark) .13f else .055f), Color.Transparent)))
        .border(1.dp, tint.copy(alpha = .13f), shape)
}
