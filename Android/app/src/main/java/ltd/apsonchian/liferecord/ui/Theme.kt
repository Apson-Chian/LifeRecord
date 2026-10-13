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
private val dark = darkColorScheme(primary = Color(0xFFA69EFF), secondary = Color(0xFF80B9FF), tertiary = Meals, background = Color.Black, surface = Color(0xFF1C1C1E), surfaceVariant = Color(0xFF2C2C32), onSurface = Color(0xFFF2F2F7), onSurfaceVariant = Color(0xFFB0AFB8))
@Composable fun LifeTheme(mode: String = "system", accent: String = "purple", content: @Composable () -> Unit) = MaterialTheme(colorScheme = (if(mode == "dark" || (mode == "system" && isSystemInDarkTheme())) dark else light).let { scheme -> scheme.copy(primary=when(accent) { "blue" -> Protein; "green" -> Color(0xFF208455); "orange" -> Color(0xFFBE681B); else -> scheme.primary }) }, typography = Typography(
    headlineLarge = TextStyle(fontSize = 34.sp, letterSpacing = (-.6).sp, fontWeight = FontWeight.Bold), headlineMedium = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold), titleMedium = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 17.sp, lineHeight = 24.sp), bodyMedium = TextStyle(fontSize = 15.sp, lineHeight = 21.sp), labelLarge = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
    bodySmall = TextStyle(fontSize = 13.sp, lineHeight = 18.sp), labelMedium = TextStyle(fontSize = 12.sp,lineHeight=16.sp), labelSmall = TextStyle(fontSize = 11.sp,lineHeight=15.sp)
), content = { CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) { content() } })
