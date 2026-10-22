package ltd.apsonchian.liferecord.ui

import android.os.Build
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.snapshots.ObserverHandle
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.ModifierNodeElement
import androidx.compose.ui.node.invalidateDraw
import androidx.compose.ui.platform.InspectorInfo
import kotlinx.coroutines.launch

/** Android 12 does not reliably invalidate effects that read another RenderNode.
 * Invalidate both capture and filter display lists after snapshot changes, without
 * changing Compose state or scheduling a permanent idle animation loop. Forced
 * capture invalidation also keeps separate dialog-window renderers up to date.
 */
internal fun Modifier.legacyBlurRedraw(force:Boolean=false): Modifier =
    if (force || Build.VERSION.SDK_INT in 31..32) then(LegacyBlurRedrawElement) else this

private object LegacyBlurRedrawElement : ModifierNodeElement<LegacyBlurRedrawNode>() {
    override fun create() = LegacyBlurRedrawNode()
    override fun update(node: LegacyBlurRedrawNode) = Unit
    override fun InspectorInfo.inspectableProperties() { name = "android12BackdropRedraw" }
    override fun equals(other: Any?) = other === this
    override fun hashCode() = javaClass.hashCode()
}

private class LegacyBlurRedrawNode : Modifier.Node(), DrawModifierNode {
    private var observer: ObserverHandle? = null
    override fun onAttach() {
        observer = Snapshot.registerApplyObserver { _, _ ->
            coroutineScope.launch { if (isAttached) invalidateDraw() }
        }
    }
    override fun onDetach() { observer?.dispose(); observer = null }
    override fun ContentDrawScope.draw() { drawContent() }
}
