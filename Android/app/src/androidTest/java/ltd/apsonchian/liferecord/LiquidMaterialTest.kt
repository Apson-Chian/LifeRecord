package ltd.apsonchian.liferecord

import android.os.Build
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.*
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
import kotlin.math.abs

@RunWith(AndroidJUnit4::class)
class LiquidMaterialTest {
    @get:Rule val compose=createEmptyComposeRule()
    private lateinit var scenario:ActivityScenario<MainActivity>
    @Before fun setup() {TestIsolation.app();scenario=ActivityScenario.launch(MainActivity::class.java)}
    @After fun close() {scenario.close()}
    private fun difference(a:Color,b:Color)=(abs(a.red-b.red)+abs(a.green-b.green)+abs(a.blue-b.blue))/3
    private fun save(image:ImageBitmap,name:String) {
        val folder=java.io.File(TestIsolation.app().filesDir,"liquid-screens").apply {mkdirs()}
        java.io.File(folder,"$name.png").outputStream().use {image.asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)}
    }
    @Test fun bevelBendsTheBackgroundWhileTheCoreStaysStableOnBothPaths() {
        Assume.assumeTrue(Build.VERSION.SDK_INT>=31)
        val depth=mutableStateOf(0.dp);val mode=mutableStateOf(LiquidOptics.Auto)
        scenario.onActivity {it.setContent {LifeTheme {
            val layer=rememberGraphicsLayer();val backdrop=remember(layer) {GlassBackdrop(layer)}
            Box(Modifier.size(280.dp,200.dp)) {
                Canvas(Modifier.fillMaxSize().glassSource(backdrop)) {
                    drawRect(Color.White);val stripe=7.dp.toPx();var x=0f
                    while(x<size.width) {drawRect(Color.Black,Offset(x,0f),Size(stripe,size.height));x+=stripe*2}
                }
                Box(Modifier.offset(23.dp,29.dp).size(220.dp,140.dp).testTag("optics")
                    .clip(RoundedCornerShape(26.dp)).liquidBackdrop(backdrop,26.dp,0.dp,depth.value,20.dp,optics=mode.value))
            }
        }}}
        if(Build.VERSION.SDK_INT>=33) compose.runOnIdle {
            assertTrue("AGSL must compile on the API35 test device",liquidEffect(Size(110f,70f),12f,13f,0f,6f,10f,false,LiquidOptics.Auto).refracted)
        }
        for(optics in LiquidOptics.entries) {
            compose.runOnIdle {mode.value=optics;depth.value=0.dp}
            val plain=compose.onNodeWithTag("optics").captureToImage().toPixelMap()
            compose.runOnIdle {depth.value=12.dp}
            val image=compose.onNodeWithTag("optics").captureToImage();val bent=image.toPixelMap()
            val core=(plain.width* .45f).toInt() until (plain.width*.55f).toInt()
            val edge=(plain.width*.02f).toInt() until (plain.width*.08f).toInt()
            val y=plain.height/2
            assertTrue("The optical core must not swim",core.map {difference(plain[it,y],bent[it,y])}.average()<.025)
            assertTrue("The bevel must displace source pixels, $optics",edge.map {difference(plain[it,y],bent[it,y])}.average()>.08)
            save(image,"refraction-${optics.name.lowercase()}")
        }
    }
    @Test fun transmissionUpdatesWithoutStalePatchesAndForegroundRemainsSharp() {
        val blue=mutableStateOf(false);val dark=mutableStateOf(false);val show=mutableStateOf(true)
        scenario.onActivity {it.setContent {LifeTheme(if(dark.value) "dark" else "light") {
            val layer=rememberGraphicsLayer();val backdrop=remember(layer) {GlassBackdrop(layer)}
            Box(Modifier.size(280.dp,180.dp).testTag("transmission-root")) {
                Canvas(Modifier.fillMaxSize().glassSource(backdrop)) {drawRect(if(blue.value) Color.Blue else Color.Red)}
                if(show.value) Box(Modifier.offset(24.dp,30.dp).size(230.dp,110.dp).testTag("material")
                    .liquidMaterial(backdrop,GlassKind.Floating,blurEnabled=true)) {
                    Canvas(Modifier.align(androidx.compose.ui.Alignment.Center).size(80.dp,16.dp).testTag("sharp-content")) {
                        drawRect(Color.White);var x=0f;val stripe=1.dp.toPx()
                        while(x<size.width) {drawRect(Color.Black,Offset(x,0f),Size(stripe,size.height));x+=stripe*2}
                    }
                }
            }
        }}}
        repeat(2) {theme ->
            compose.runOnIdle {dark.value=theme==1;blue.value=false;show.value=true}
            fun color()=compose.onNodeWithTag("material").captureToImage().toPixelMap().let {it[(it.width*.10f).toInt(),it.height/2]}
            assertTrue("Transmission retains red",color().let {it.red-it.blue}>.25f)
            repeat(3) {
                compose.runOnIdle {blue.value=true};assertTrue("No old red tile",color().let {it.blue-it.red}>.25f)
                compose.runOnIdle {show.value=false};compose.waitForIdle()
                compose.runOnIdle {blue.value=false;show.value=true};assertTrue("Reentry samples the new source",color().let {it.red-it.blue}>.25f)
            }
            val pixels=compose.onNodeWithTag("sharp-content").captureToImage().toPixelMap()
            val row=(0 until pixels.width).map {pixels[it,pixels.height/2].luminance()}
            assertTrue("Foreground must bypass all filters",row.max()-row.min()>.90f)
            save(compose.onNodeWithTag("transmission-root").captureToImage(),"transmission-${if(theme==0) "light" else "dark"}")
        }
    }
    @Test fun fallbackIsReadableAndHasContactDepthWithoutSamplingTheSource() {
        val blue=mutableStateOf(false)
        scenario.onActivity {it.setContent {LifeTheme {
            val layer=rememberGraphicsLayer();val backdrop=remember(layer) {GlassBackdrop(layer)}
            Box(Modifier.size(280.dp,200.dp).testTag("fallback-root")) {
                Canvas(Modifier.fillMaxSize().glassSource(backdrop)) {drawRect(if(blue.value) Color.Blue else Color.Red)}
                Box(Modifier.offset(24.dp,30.dp).size(230.dp,110.dp).testTag("fallback-card").liquidMaterial(backdrop,blurEnabled=false)) {Text("清晰的营养数据",Modifier.padding(20.dp))}
            }
        }}}
        fun corner()=compose.onNodeWithTag("fallback-card").captureToImage().toPixelMap().let {it[it.width/2,(it.height*.75f).toInt()]}
        val before=corner();compose.runOnIdle {blue.value=true};val after=corner()
        assertTrue("Fallback must remain near opaque",difference(before,after)<.04f)
        assertTrue("Fallback keeps a light reading surface",after.luminance()>.85f)
        val image=compose.onNodeWithTag("fallback-root").captureToImage();val p=image.toPixelMap()
        val x=p.width/2
        val near=p[x,(p.height*.71f).toInt()].blue
        val far=p[x,(p.height*.95f).toInt()].blue
        assertTrue("The card casts a contact shadow",near<far-.005f)
        save(image,"fallback-depth")
    }
    @Test fun dialogSamplesTheActivityAcrossWindowsAndKeepsItsActions() {
        val blue=mutableStateOf(false);val open=mutableStateOf(true);var confirmed=0
        scenario.onActivity {it.setContent {LifeTheme {
            val layer=rememberGraphicsLayer();val backdrop=remember(layer) {GlassBackdrop(layer)}
            Canvas(Modifier.fillMaxSize().glassSource(backdrop)) {drawRect(if(blue.value) Color.Blue else Color.Red)}
            CompositionLocalProvider(LocalGlassPage provides backdrop) {
                if(open.value) GlassAlertDialog(onDismissRequest={open.value=false},modifier=Modifier.testTag("liquid-dialog"),
                    title={Text("清晰提示")},text={Text("文字保持清晰，背景折射和高光在文字下面。")},
                    confirmButton={TextButton(onClick={confirmed++;open.value=false}) {Text("保留操作")}})
            }
        }}}
        fun sample()=compose.onNodeWithTag("liquid-dialog").captureToImage().toPixelMap().let {it[(it.width*.88f).toInt(),it.height/2]}
        val red=sample();save(compose.onNodeWithTag("liquid-dialog").captureToImage(),"dialog-before")
        compose.runOnIdle {blue.value=true}
        compose.waitUntil(2000) {difference(red,sample())>.035f}
        val changed=sample()
        save(compose.onNodeWithTag("liquid-dialog").captureToImage(),"dialog-after")
        assertTrue("Dialog must repaint its underlying activity: $red -> $changed",difference(red,changed)>.035f)
        save(compose.onNodeWithTag("liquid-dialog").captureToImage(),"dialog")
        compose.onNodeWithText("保留操作").performClick();compose.runOnIdle {assertEquals(1,confirmed)}
        compose.onNodeWithText("清晰提示").assertDoesNotExist()
    }
}
