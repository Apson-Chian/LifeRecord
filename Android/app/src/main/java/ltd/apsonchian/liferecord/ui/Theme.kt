package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Match iOS AppTheme: accent, protein (blue), carbs (orange), meals (red).
val Purple = Color(0xFF5752F5)
val Protein = Color(0xFF338CFA)
val Carbs = Color(0xFFF2A338)
val Meals = Color(0xFFF04059)
val Fat = Color(0xFFE059AB)
private val light = lightColorScheme(primary = Purple, secondary = Protein, tertiary = Meals, background = Color(0xFFF2F2F7), surface = Color.White, surfaceVariant = Color(0xFFEBEDF2), onSurface = Color(0xFF20232B), onSurfaceVariant = Color(0xFF626875))
private val dark = darkColorScheme(primary = Color(0xFFA69EFF), secondary = Color(0xFF80B9FF), tertiary = Meals, background = Color(0xFF0D0E12), surface = Color(0xFF1C1C1E), surfaceVariant = Color(0xFF292E38), onSurface = Color(0xFFF5F6F8), onSurfaceVariant = Color(0xFFB0AFB8))
// Optical sizes for the same hierarchy as SwiftUI; keep Android's font scaling.
private fun appText(size: Int, leading: Int, weight: FontWeight = FontWeight.Normal, tracking: Float = 0f) = TextStyle(
    fontFamily=FontFamily.SansSerif, fontSize=size.sp, lineHeight=leading.sp, fontWeight=weight,
    letterSpacing=tracking.sp, platformStyle=PlatformTextStyle(includeFontPadding=false),
    lineHeightStyle=LineHeightStyle(LineHeightStyle.Alignment.Center,LineHeightStyle.Trim.Both),
)
internal object AppTypography {
    val chatBody=appText(15,22)
    val chatInput=appText(15,21)
    val chatName=appText(12,16,FontWeight.Medium)
    val number=appText(34,40,FontWeight.SemiBold,-.7f)
}
private val appTypography=Typography(
    displayLarge=appText(34,40,FontWeight.Bold,-.7f),displayMedium=appText(28,34,FontWeight.Bold),displaySmall=appText(24,30,FontWeight.SemiBold),
    headlineLarge=appText(34,40,FontWeight.Bold,-.5f),headlineMedium=appText(22,28,FontWeight.Bold),headlineSmall=appText(20,26,FontWeight.SemiBold),
    titleLarge=appText(17,23,FontWeight.SemiBold),titleMedium=appText(16,22,FontWeight.SemiBold),titleSmall=appText(15,20,FontWeight.SemiBold),
    bodyLarge=appText(16,22),bodyMedium=appText(15,21),bodySmall=appText(13,18),
    labelLarge=appText(15,20,FontWeight.SemiBold),labelMedium=appText(12,16),labelSmall=appText(11,14),
)
@Composable fun LifeTheme(mode: String = "system", accent: String = "purple", content: @Composable () -> Unit) = MaterialTheme(
    colorScheme=(if(mode == "dark" || (mode == "system" && isSystemInDarkTheme())) dark else light).let { scheme -> scheme.copy(primary=when(accent) { "blue" -> Protein; "green" -> Color(0xFF208455); "orange" -> Color(0xFFBE681B); else -> scheme.primary }) },
    typography=appTypography,
    content={CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface, LocalMotionEnabled provides observeMotionPreference(), LocalPowerSave provides observePowerSaveMode()) {content()}},
)
