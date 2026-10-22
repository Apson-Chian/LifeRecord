package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

/** One selection language, with a wrapping layout for large fonts and narrow screens. */
@Composable internal fun ChoiceControl(choices: List<Pair<String, String>>, selected: String, select: (String) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val large = LocalDensity.current.fontScale > 1.3f || maxWidth < (choices.size * 70).dp
        @Composable fun choice(key: String, label: String, modifier: Modifier) {
            val source=remember {MutableInteractionSource()}
            Box(modifier.heightIn(min = 48.dp).springPress(source).clip(RoundedCornerShape(9.dp))
                .background(if (key == selected) MaterialTheme.colorScheme.surface else Color.Transparent)
                .selectable(key == selected, interactionSource=source, indication=LocalIndication.current, role = Role.RadioButton, onClick = { select(key) })
                .padding(horizontal = 8.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
                Text(label, style = MaterialTheme.typography.bodySmall,
                    color = if (key == selected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (large) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant).padding(3.dp).selectableGroup()) {
                choices.forEach { (key, label) -> choice(key, label, Modifier.fillMaxWidth()) }
            }
        } else {
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant).padding(3.dp).selectableGroup()) {
                choices.forEach { (key, label) -> choice(key, label, Modifier.weight(1f)) }
            }
        }
    }
}
