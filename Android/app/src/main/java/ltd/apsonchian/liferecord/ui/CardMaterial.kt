package ltd.apsonchian.liferecord.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Data surfaces retain more transmission tint than floating navigation. */
@Composable
internal fun Modifier.cardMaterial(tint:Color=MaterialTheme.colorScheme.primary,radius:Dp=26.dp):Modifier =
    liquidMaterial(LocalGlassAmbient.current,GlassKind.Card,radius,tint)
