package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController

/** Observe unhandled taps only: fields, buttons, text selection and scrolling win. */
@Composable
internal fun Modifier.dismissKeyboardOnBackgroundTap(): Modifier {
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    return pointerInput(focus, keyboard) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            if (!down.isConsumed) {
                val up = waitForUpOrCancellation()
                if (up != null && !up.isConsumed) {
                    focus.clearFocus()
                    keyboard?.hide()
                }
            }
        }
    }
}
