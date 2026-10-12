package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val Purple = Color(0xFF6954D9)
val Protein = Color(0xFF8C70EF)
val Carbs = Color(0xFF4F9FDE)
val Meals = Color(0xFFED9C68)
private val light = lightColorScheme(primary = Purple, secondary = Color(0xFF447BB3), tertiary = Meals, background = Color(0xFFF6F5FA), surface = Color.White, surfaceVariant = Color(0xFFF0EDF9), onSurface = Color(0xFF252237), onSurfaceVariant = Color(0xFF7C778C))
private val dark = darkColorScheme(primary = Color(0xFFB4A4FF), secondary = Color(0xFF90C9F6), tertiary = Meals, background = Color(0xFF15131E), surface = Color(0xFF201D2D), surfaceVariant = Color(0xFF302B41), onSurface = Color(0xFFF3EEFF), onSurfaceVariant = Color(0xFFBDB5CF))
@Composable fun LifeTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = if(isSystemInDarkTheme()) dark else light, typography = Typography(
    headlineLarge = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Bold), headlineMedium = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold), titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 25.sp), bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 22.sp), labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium)
), content = content)
