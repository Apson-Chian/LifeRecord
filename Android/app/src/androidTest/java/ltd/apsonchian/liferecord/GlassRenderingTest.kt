package ltd.apsonchian.liferecord

import android.os.Build
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
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
class GlassRenderingTest {
    @get:Rule val compose = createEmptyComposeRule()
    private lateinit var scenario: ActivityScenario<MainActivity>

    @Before fun setup() {
        TestIsolation.app()
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }
    @After fun close() { scenario.close() }

    @Test fun progressiveBlurHasClearTopAndSoftBottomInBothThemes() {
        Assume.assumeTrue(Build.VERSION.SDK_INT >= 31)
        verifyBlur(bands = false)
    }

    @Test fun android12BandsHaveClearTopAndSoftBottom() {
        Assume.assumeTrue(Build.VERSION.SDK_INT >= 31)
        verifyBlur(bands = true)
    }

    @Test fun blurredPixelsFollowSourceLayerChangesAndNavigationReentry() {
        Assume.assumeTrue(Build.VERSION.SDK_INT >= 31)
        val blue=mutableStateOf(false)
        val visible=mutableStateOf(true)
        scenario.onActivity { activity -> activity.setContent {
            LifeTheme {
                val layer=rememberGraphicsLayer();val backdrop=remember(layer) {GlassBackdrop(layer)}
                Box(Modifier.padding(24.dp).size(260.dp,300.dp).testTag("live-blur")) {
                    Box(Modifier.fillMaxSize().glassSource(backdrop)) {
                        Canvas(Modifier.fillMaxSize().graphicsLayer {translationX=if(blue.value) 1f else 0f}) {
                            drawRect(if(blue.value) Color.Blue else Color.Red)
                        }
                    }
                    if(visible.value) ProgressiveBackdrop(backdrop,Modifier.fillMaxSize(),blurEnabled=true)
                }
            }
        }}
        fun sample()=compose.onNodeWithTag("live-blur").captureToImage().toPixelMap().let {it[it.width/2,(it.height*.78f).toInt()]}
        assertTrue(sample().red>.65f)
        repeat(3) {
            compose.runOnIdle {blue.value=true};assertTrue("Blur must repaint blue, including API31",sample().blue>.65f)
            compose.runOnIdle {visible.value=false};sample()
            compose.runOnIdle {blue.value=false;visible.value=true};assertTrue("No stale patch after reentry",sample().red>.65f)
        }
    }

    private fun verifyBlur(bands: Boolean) {
        val dark = mutableStateOf(false)
        val inverted = mutableStateOf(false)
        scenario.onActivity { activity -> activity.setContent {
            LifeTheme(if (dark.value) "dark" else "light") {
                val layer = rememberGraphicsLayer()
                val backdrop = remember(layer) { GlassBackdrop(layer) }
                // A displaced source and target exercise root-to-local sampling alignment.
                Box(Modifier.padding(start = 23.dp, top = 31.dp).size(280.dp, 320.dp).testTag("blur-fixture")) {
                    Canvas(Modifier.fillMaxSize().glassSource(backdrop)) {
                        val stripe = 6.dp.toPx()
                        val shift = if (inverted.value) stripe else 0f
                        drawRect(Color.White)
                        var x = -stripe * 2
                        while (x < size.width) {
                            drawRect(Color.Black, Offset(x + shift, 0f), Size(stripe, size.height))
                            x += stripe * 2
                        }
                    }
                    Box(Modifier.fillMaxSize()) {
                        if (bands) {
                            listOf(.22f, .55f, 1f).forEachIndexed { index, fraction ->
                                BackdropLayer(backdrop, Modifier.fillMaxSize(), 24.dp * fraction) { size, padding, radius ->
                                    ProgressiveBlurEffects.band(size, padding, radius, index)
                                }
                            }
                        } else {
                            ProgressiveBackdrop(backdrop, Modifier.fillMaxSize(), blurEnabled = true)
                        }
                    }
                }
            }
        } }
        repeat(2) { theme ->
            compose.runOnIdle { dark.value = theme == 1 }
            val image = compose.onNodeWithTag("blur-fixture").captureToImage()
            val pixels = image.toPixelMap()
            val clear = contrast(pixels, .04f)
            val soft = contrast(pixels, .90f)
            if (!bands) {
                listOf(.55f, .65f, .75f, .85f, .95f, .995f).forEach { row ->
                    assertTrue("No sampling stripes at $row", contrast(pixels, row) < .10f)
                }
            }
            assertTrue("Clear edge contrast: $clear", clear > .75f)
            assertTrue("Radius must increase downwards: clear=$clear soft=$soft", soft < clear * .35f)
            val before = pixels[pixels.width / 2, (pixels.height * .04f).toInt()].luminance()
            compose.runOnIdle { inverted.value = !inverted.value }
            val updated = compose.onNodeWithTag("blur-fixture").captureToImage().toPixelMap()
            val after = updated[updated.width / 2, (updated.height * .04f).toInt()].luminance()
            assertTrue("Source must update without stale frames", kotlin.math.abs(after - before) > .65f)
            save(image, "${if (bands) "bands" else "progressive"}-${if (theme == 1) "dark" else "light"}")
        }
    }

    @Test fun fallbackLeavesClearEdgeAndDoesNotInterceptTouches() {
        var taps = 0
        scenario.onActivity { activity -> activity.setContent {
            LifeTheme {
                val layer = rememberGraphicsLayer()
                val backdrop = remember(layer) { GlassBackdrop(layer) }
                Box(Modifier.size(280.dp, 320.dp).testTag("fallback-fixture")) {
                    Canvas(Modifier.fillMaxSize().glassSource(backdrop).clickable { taps++ }) { drawRect(Color.Black) }
                    ProgressiveBackdrop(backdrop, Modifier.fillMaxSize(), blurEnabled = false)
                }
            }
        } }
        compose.onNodeWithTag("fallback-fixture").performTouchInput { click(center) }
        compose.runOnIdle { assertEquals(1, taps) }
        val image = compose.onNodeWithTag("fallback-fixture").captureToImage()
        val pixels = image.toPixelMap()
        assertTrue(pixels[pixels.width / 2, 1].luminance() < .02f)
        assertTrue(pixels[pixels.width / 2, pixels.height - 2].luminance() > .65f)
        save(image, "fallback")
    }

    private fun contrast(pixels: PixelMap, fraction: Float): Float {
        val row = (pixels.height * fraction).toInt()
        val values = (pixels.width / 4 until pixels.width * 3 / 4).map { pixels[it, row].luminance() }
        return values.max() - values.min()
    }
    private fun save(image: ImageBitmap, name: String) {
        val folder = java.io.File(TestIsolation.app().filesDir, "glass-screens").apply { mkdirs() }
        java.io.File(folder, "$name.png").outputStream().use {
            image.asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
    }
}
