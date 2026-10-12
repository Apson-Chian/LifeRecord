package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Match iOS AppTheme: accent, protein (blue), carbs (orange), meals (red).
val Purple = Color(0xFF5752F5)
val Protein = Color(0xFF338CFA)
val Carbs = Color(0xFFF2A338)
val Meals = Color(0xFFF04059)
val Fat = Color(0xFFE059AB)
private val light = lightColorScheme(primary = Purple, secondary = Protein, tertiary = Meals, background = Color(0xFFF2F2F7), surface = Color.White, surfaceVariant = Color(0xFFEAEAF3), onSurface = Color(0xFF1C1C1E), onSurfaceVariant = Color(0xFF686872))
private val dark = darkColorScheme(primary = Color(0xFFA69EFF), secondary = Color(0xFF80B9FF), tertiary = Meals, background = Color(0xFF0E0E12), surface = Color(0xFF1C1C1E), surfaceVariant = Color(0xFF2C2C32), onSurface = Color(0xFFF2F2F7), onSurfaceVariant = Color(0xFFB0AFB8))
@Composable fun LifeTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = if(isSystemInDarkTheme()) dark else light, typography = Typography(
    headlineLarge = TextStyle(fontSize = 32.sp, letterSpacing = (-.6).sp, fontWeight = FontWeight.Bold), headlineMedium = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold), titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 25.sp), bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 22.sp), labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium)
), content = { CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) { content() } })
