package ltd.apsonchian.liferecord.ui

import android.view.View
import android.view.ViewTreeObserver
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.ModifierNodeElement
import androidx.compose.ui.node.invalidateDraw
import androidx.compose.ui.platform.InspectorInfo

/** Different windows have different render loops. Repaint the dialog after the
 * activity records a frame, rather than keeping a cached shader input forever.
 * No state writes in drawing and no permanent animation/bitmap capture loop.
 */
internal fun Modifier.crossWindowBackdropRedraw(source:View?,target:View):Modifier =
    if(source!=null && source.rootView!==target.rootView) then(CrossWindowElement(source,target)) else this

private data class CrossWindowElement(val source:View,val target:View):ModifierNodeElement<CrossWindowNode>() {
    override fun create()=CrossWindowNode(source,target)
    override fun update(node:CrossWindowNode) {node.update(source,target)}
    override fun InspectorInfo.inspectableProperties() {name="crossWindowGlassRedraw"}
}
private class CrossWindowNode(var source:View,var target:View):Modifier.Node(),DrawModifierNode {
    private val redraw=Runnable {if(isAttached) invalidateDraw()}
    private val listener=ViewTreeObserver.OnDrawListener {
        target.removeCallbacks(redraw);target.postOnAnimation(redraw)
    }
    override fun onAttach() {source.viewTreeObserver.addOnDrawListener(listener);target.postOnAnimation(redraw)}
    override fun onDetach() {
        if(source.viewTreeObserver.isAlive) source.viewTreeObserver.removeOnDrawListener(listener)
        target.removeCallbacks(redraw)
    }
    fun update(nextSource:View,nextTarget:View) {
        if(source===nextSource && target===nextTarget) return
        if(isAttached) onDetach()
        source=nextSource;target=nextTarget
        if(isAttached) onAttach()
    }
    override fun ContentDrawScope.draw() {drawContent()}
}
