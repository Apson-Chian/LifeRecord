package ltd.apsonchian.liferecord

import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import ltd.apsonchian.liferecord.ui.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SpringMotionTest {
    @get:Rule val compose=createEmptyComposeRule()
    private lateinit var scenario:ActivityScenario<MainActivity>
    @Before fun setup() {TestIsolation.app();scenario=ActivityScenario.launch(MainActivity::class.java)}
    @After fun close() {compose.mainClock.autoAdvance=true;scenario.close()}

    private fun navigation(motion:Boolean=true) {
        scenario.onActivity { it.setContent {
            LifeTheme { CompositionLocalProvider(LocalMotionEnabled provides motion) {
                var selected by remember {mutableIntStateOf(0)}
                val layer=rememberGraphicsLayer()
                Box(Modifier.padding(20.dp).width(360.dp).height(100.dp)) {
                    GlassNavigationBar(remember(layer) {GlassBackdrop(layer)},selected,{selected=it})
                }
            } }
        } }
        compose.waitForIdle()
    }
    private fun indicator()=compose.onNodeWithTag("glass-selection",useUnmergedTree=true).fetchSemanticsNode().boundsInRoot

    @Test fun navigationFollowsFingerAndRegrabsTheMovingPresentation() {
        navigation();compose.mainClock.autoAdvance=false
        val start=indicator().left
        val bar=compose.onNodeWithTag("glass-navigation")
        bar.performTouchInput {down(Offset(width*.12f,height*.5f));moveBy(Offset(110f,0f),100)}
        compose.mainClock.advanceTimeByFrame()
        val first=indicator().left
        bar.performTouchInput {moveBy(Offset(50f,0f),100)}
        compose.mainClock.advanceTimeByFrame()
        assertTrue(first>start+50f)
        assertEquals("During drag there is no easing lag",50f,indicator().left-first,3f)
        val beforeRelease=indicator().left
        bar.performTouchInput {advanceEventTime(200);up()}
        compose.mainClock.advanceTimeByFrame()
        assertEquals("Release must not jump to the old selected slot",beforeRelease,indicator().left,12f)
        compose.mainClock.advanceTimeBy(48)
        val moving=indicator().left
        bar.performTouchInput {down(center)}
        compose.mainClock.advanceTimeByFrame()
        assertEquals("Regrab freezes the live spring",moving,indicator().left,12f)
        bar.performTouchInput {moveBy(Offset(-45f,0f),100)}
        compose.mainClock.advanceTimeByFrame()
        assertEquals(-45f,indicator().left-moving,12f)
        bar.performTouchInput {up()};compose.mainClock.advanceTimeBy(1000)
    }

    @Test fun reducedMotionHasNoSelectionTravelOrPressTransform() {
        navigation(motion=false);compose.mainClock.autoAdvance=false
        compose.onNodeWithTag("tab-3").performClick()
        compose.mainClock.advanceTimeBy(32)
        val tab=compose.onNodeWithTag("tab-3").fetchSemanticsNode().boundsInRoot
        assertEquals(tab.left,indicator().left,2f)
        compose.onNodeWithTag("tab-3").performTouchInput {down(center)}
        compose.mainClock.advanceTimeBy(160)
        assertEquals(tab.width,compose.onNodeWithTag("tab-3").fetchSemanticsNode().boundsInRoot.width,1f)
        compose.onNodeWithTag("tab-3").performTouchInput {up()}
    }

    @Test fun pressCanCancelAndRetargetWithoutActivatingTheButton() {
        var clicks=0
        scenario.onActivity { it.setContent {LifeTheme {AppButton({clicks++},Modifier.padding(24.dp).width(220.dp).testTag("press-target")) {Text("保存")}}} }
        compose.waitForIdle();compose.mainClock.autoAdvance=false
        val button=compose.onNodeWithTag("press-target")
        val width=button.fetchSemanticsNode().boundsInRoot.width
        button.performTouchInput {down(center)};compose.mainClock.advanceTimeBy(160)
        assertTrue(button.fetchSemanticsNode().boundsInRoot.width<width-1f)
        button.performTouchInput {cancel()};compose.mainClock.advanceTimeBy(96)
        val returning=button.fetchSemanticsNode().boundsInRoot.width
        button.performTouchInput {down(center)};compose.mainClock.advanceTimeBy(160)
        assertTrue("Repress reverses the returning spring",button.fetchSemanticsNode().boundsInRoot.width<returning)
        button.performTouchInput {cancel()};compose.mainClock.advanceTimeBy(1000)
        assertEquals(width,button.fetchSemanticsNode().boundsInRoot.width,1f)
        assertEquals(0,clicks)
        compose.mainClock.autoAdvance=true;button.performClick();compose.runOnIdle {assertEquals(1,clicks)}
    }

    @Test fun shortPhotoDragReturnsThroughASpringAndCanBeGrabbedAgain() {
        val bitmap=android.graphics.Bitmap.createBitmap(40,60,android.graphics.Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.RED)
        val data=java.io.ByteArrayOutputStream().also {bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)}.toByteArray()
        bitmap.recycle()
        var closed=false
        scenario.onActivity {
            val model=AppViewModel(TestIsolation.app())
            it.setContent {LifeTheme {PhotoViewer(model,data) {closed=true}}}
        }
        compose.waitUntil(5000) {compose.onAllNodesWithTag("gallery-image-single").fetchSemanticsNodes().isNotEmpty()}
        compose.waitForIdle();compose.mainClock.autoAdvance=false
        val viewer=compose.onNodeWithTag("photo-viewer")
        fun top()=compose.onNodeWithTag("gallery-image-single").fetchSemanticsNode().boundsInRoot.top
        val start=top()
        viewer.performTouchInput {down(center);moveBy(Offset(0f,100f),600)}
        compose.mainClock.advanceTimeByFrame()
        val held=top();assertTrue("Held photo must follow finger: start=$start held=$held",held>start+30f)
        viewer.performTouchInput {up()};compose.mainClock.advanceTimeBy(32)
        val returning=top()
        assertTrue("No teleport when a short drag is released",returning>start+10f)
        viewer.performTouchInput {down(center);moveBy(Offset(0f,50f),150)}
        compose.mainClock.advanceTimeByFrame()
        assertTrue("A returning photo remains draggable",top()>returning)
        viewer.performTouchInput {cancel()};compose.mainClock.advanceTimeBy(1000)
        assertEquals(start,top(),2f);assertFalse(closed)
    }
}
