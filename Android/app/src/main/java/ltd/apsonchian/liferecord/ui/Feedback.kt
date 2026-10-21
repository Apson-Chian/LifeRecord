package ltd.apsonchian.liferecord.ui

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

/** View feedback respects the user's system haptics preference and needs no permission. */
@Composable internal fun rememberActionFeedback(): (Boolean) -> Unit {
    val view = LocalView.current
    return remember(view) { { success ->
        view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) {
            if (success) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.REJECT
        } else HapticFeedbackConstants.VIRTUAL_KEY)
        Unit
    } }
}
