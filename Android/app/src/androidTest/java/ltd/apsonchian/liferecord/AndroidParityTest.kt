package ltd.apsonchian.liferecord

import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.*
import ltd.apsonchian.liferecord.ui.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.time.LocalDate

@RunWith(AndroidJUnit4::class)
class AndroidParityTest {
    @get:Rule val compose = createEmptyComposeRule()
    private lateinit var app: IsolatedLifeRecordApplication
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var vm: AppViewModel
    @Before fun setup() {
        app=TestIsolation.app();app.store.clearAll();app.secrets.clear()
        app.store.set("onboarded","yes");app.store.set("appearance","light")
        scenario=ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity { vm=ViewModelProvider(it)[AppViewModel::class.java] }
    }
    @After fun cleanup() { scenario.close();app.store.clearAll();app.secrets.clear();app.photos.clearAll() }
    private fun meal() {
        compose.onNodeWithContentDescription("添加记录").performClick()
        compose.onAllNodesWithText("记一餐").onLast().performClick()
        compose.onNodeWithText("编辑餐食").assertIsDisplayed()
    }
    private fun hideKeyboard() { androidx.test.espresso.Espresso.closeSoftKeyboard();compose.waitForIdle() }
    private fun field(label:String,value:String) { compose.onNodeWithContentDescription(label).performScrollTo().performTextReplacement(value) }
    private fun screenshot(name:String,awaitCompose:Boolean=true) {
        if(awaitCompose) compose.waitForIdle()
        android.os.SystemClock.sleep(400)
        val folder=java.io.File(app.filesDir,"parity-completed").apply {mkdirs()}
        val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()!!
        java.io.File(folder,"$name.png").outputStream().use {bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
    }
    @Test fun mealDraftRestoresFieldsModeAndOriginalIdentityAcrossRecreation() {
        meal();field("餐食名称","保留中的餐食");field("热量 kcal","456");hideKeyboard()
        compose.onNodeWithText("AI 识别 / 修改").performScrollTo().performClick()
        compose.onNodeWithText("营养成分表").performScrollTo().performClick()
        field("描述食物、份量或修改要求","吃了包装的半份");hideKeyboard()
        scenario.recreate()
        compose.onNodeWithText("编辑餐食").assertIsDisplayed()
        compose.onNodeWithContentDescription("餐食名称").performScrollTo().assertTextContains("保留中的餐食")
        compose.onNodeWithContentDescription("热量 kcal").performScrollTo().assertTextContains("456")
        compose.onNodeWithText("营养成分表").performScrollTo().assertIsSelected()
        compose.onNodeWithContentDescription("描述食物、份量或修改要求").performScrollTo().assertTextContains("吃了包装的半份")
        screenshot("meal-restored")
        compose.onNodeWithText("保存").performClick();compose.waitForIdle()
        assertEquals("保留中的餐食",app.store.load().records.single().title)
        assertEquals(456.0,app.store.load().records.single().json.getDouble("calories"),0.0)
    }
    @Test fun dirtyDismissalCanContinueOrDiscardWithoutSaving() {
        meal();field("餐食名称","放弃的草稿");hideKeyboard()
        compose.onNodeWithText("取消").performClick()
        compose.onNodeWithText("放弃未保存的更改？").assertIsDisplayed()
        compose.onNodeWithText("继续编辑").performClick()
        compose.onNodeWithContentDescription("餐食名称").assertTextContains("放弃的草稿")
        compose.onNodeWithText("取消").performClick();compose.onNodeWithText("放弃更改").performClick()
        compose.onNodeWithText("编辑餐食").assertDoesNotExist();assertTrue(app.store.load().records.isEmpty())
    }
    @Test fun bodyAndWorkoutExerciseDraftsRestore() {
        compose.onNodeWithContentDescription("添加记录").performClick();compose.onAllNodesWithText("记体重").onLast().performClick()
        field("体重 kg","73.4");hideKeyboard();scenario.recreate()
        compose.onNodeWithContentDescription("体重 kg").assertTextContains("73.4")
        compose.onNodeWithText("保存").performClick();compose.waitForIdle()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("补记"))
        val target=compose.onNodeWithText("补记").fetchSemanticsNode().boundsInRoot
        val bar=compose.onNodeWithTag("glass-navigation").fetchSemanticsNode().boundsInRoot
        // Leave room for the navigation's touch target and rounded card shadows.
        if(target.bottom>bar.top-240f) compose.onNode(hasScrollAction()).performTouchInput {swipeUp(startY=height*.75f,endY=height*.35f,durationMillis=250)}
        compose.onNodeWithText("补记").performClick()
        compose.onNodeWithText("具体动作与组数（可选）").performScrollTo().performClick()
        compose.onNodeWithText("添加动作").performScrollTo().performClick()
        field("动作","哑铃划船");field("部位","背部");hideKeyboard()
        compose.onNodeWithText("添加一组").performScrollTo().performClick();field("次数（可选）","12");hideKeyboard()
        scenario.recreate()
        compose.onNodeWithContentDescription("动作").assertTextContains("哑铃划船")
        compose.onNodeWithContentDescription("次数（可选）").performScrollTo().assertTextContains("12")
        compose.onNodeWithText("完成").performClick()
        compose.onNodeWithText("哑铃划船 · 1 组").assertExists()
    }
    @Test fun photoDraftSaverStoresOnlyPrivateReferencesAndRestoresAcrossInstances() {
        val owner=java.util.UUID.randomUUID().toString()
        val bytes=byteArrayOf(7,8,9,10)
        val photos=Photos(app)
        val refs=photos.stageDraft(owner,listOf(bytes,bytes))
        assertEquals(refs[0],refs[1]);assertTrue(refs.all {it.matches(Regex("[a-f0-9]{64}\\.jpg"))})
        assertArrayEquals(bytes,Photos(app).readDraft(owner,refs[0]))
        assertThrows(IllegalArgumentException::class.java) {photos.readDraft(owner,"../outside.jpg")}
        photos.discardDraft(owner);assertNull(photos.readDraft(owner,refs[0]))
    }
    @Test fun historicalRecordIdsRemainValidDraftOwnersAndCannotEscapePrivateStorage() {
        val owner="old_record/早餐"
        val bytes=byteArrayOf(1,4,9)
        val refs=app.photos.stageDraft(owner,listOf(bytes))
        assertArrayEquals(bytes,Photos(app).readDraft(owner,refs.single()))
        assertNull(Photos(app).readDraft("another-record",refs.single()))
        app.photos.discardDraft(owner)
    }
    @Test fun photoGalleryPagesAndKeepsZoomGestureSeparateFromPaging() {
        fun image(color:Int):ByteArray {
            val bitmap=android.graphics.Bitmap.createBitmap(30,60,android.graphics.Bitmap.Config.ARGB_8888).apply {eraseColor(color)}
            return java.io.ByteArrayOutputStream().use {bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG,90,it);bitmap.recycle();it.toByteArray()}
        }
        val photos=listOf(image(android.graphics.Color.RED),image(android.graphics.Color.BLUE),image(android.graphics.Color.GREEN))
        scenario.onActivity {it.setContent {LifeTheme {PhotoGallery(vm,photos.mapIndexed {i,bytes -> GalleryPhoto("$i") {bytes}},1,{})}}}
        compose.onNodeWithText("2 / 3").assertIsDisplayed()
        compose.onNodeWithContentDescription("下一张照片").performClick();compose.onNodeWithText("3 / 3").assertIsDisplayed()
        compose.onNodeWithContentDescription("下一张照片").assertIsNotEnabled()
        compose.onNodeWithContentDescription("上一张照片").performClick();compose.onNodeWithText("2 / 3").assertIsDisplayed()
        compose.onNodeWithTag("photo-viewer").performTouchInput {doubleClick(center)}
        compose.onNodeWithText("双击还原后切换照片").assertExists()
        compose.onNodeWithContentDescription("下一张照片").assertIsNotEnabled()
        compose.onNodeWithTag("photo-viewer").performTouchInput {doubleClick(center)}
        compose.onNodeWithContentDescription("下一张照片").assertIsEnabled()
        screenshot("photo-gallery")
    }
    @Test fun nutritionModesReachTheActualRequestWithoutWritingRecords() = runBlocking {
        val systems=mutableListOf<String>()
        val network=Network(OkHttpClient.Builder().addInterceptor {chain ->
            val buffer=okio.Buffer();chain.request().body!!.writeTo(buffer)
            val body=JSONObject(buffer.readUtf8());systems+=body.getJSONArray("messages").getJSONObject(0).getString("content")
            val content=JSONObject().put("name","待复核").put("calories",123).put("protein",4).put("carbs",5).put("fat",6).put("fiber",1).put("note","按半份估算").toString()
            val result=JSONObject().put("choices",JSONArray().put(JSONObject().put("message",JSONObject().put("content",content))))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("fixture").body(result.toString().toResponseBody("application/json".toMediaType())).build()
        }.build())
        val model=AppViewModel(app,network)
        model.config.value=providerConfig("自定义").put("endpoint","https://fixture.invalid/chat/completions").put("auth","Bearer").put("model","fixture")
        app.secrets.save(apiScope(model.config.value),"fixture-local-only")
        MealScanMode.entries.forEach {mode -> assertEquals("待复核",model.nutrition("实际吃了半份",emptyList(),null,mode).getString("name"))}
        assertEquals(3,systems.size);assertTrue(systems[0].contains("不要重复"));assertTrue(systems[1].contains("每100g"));assertTrue(systems[2].contains("过敏原"));assertTrue(app.store.load().records.isEmpty())
    }
    @Test fun bodyOverviewShowsBothSeriesTodayAndLazyHistoryWithAccessibleReadings() {
        val records=(0..30).map {day -> Record.create(RecordType.BODY,LocalDate.now().minusDays(day.toLong()).epochAt(java.time.LocalTime.of(8,0)).coerceAtMost(now()-1)).apply {json.put("weight",70.0+day%3)} }
        scenario.onActivity {it.setContent {LifeTheme {BodyOverviewPage(records,{}, {})}}}
        compose.onNodeWithText("每日中位数与趋势").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("虚线 · 每日中位数").assertExists();compose.onNodeWithText("实线 · 趋势体重").assertExists()
        val chart=compose.onNodeWithContentDescription("体重走势，虚线为每日中位数，实线为趋势体重")
        chart.assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.StateDescription))
        val actions=chart.fetchSemanticsNode().config[SemanticsActions.CustomActions]
        compose.runOnIdle {assertTrue(actions.first {it.label=="上一日测量"}.action())}
        screenshot("body-dual-chart")
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("查看历史测量 · 31 条"))
        compose.onNodeWithText("查看历史测量 · 31 条").performClick()
        screenshot("body-overview")
    }
    @Test fun mealHistoryCanReachLastOfThousandRecordsWithoutComposingThemAll() {
        val records=(0 until 1000).map {index -> Record.create(RecordType.MEAL,now()-index*60).apply {json.put("name","历史餐食-$index")} }
        scenario.onActivity {it.setContent {LifeTheme {MealHistory(vm,Snapshot(records,defaultProfile(),emptyList()),false,{}, {})}}}
        compose.onNodeWithText("历史餐食-999").assertDoesNotExist()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("历史餐食-999"))
        compose.onNodeWithText("历史餐食-999").assertExists()
    }
    @Test fun restoredEditorCannotResurrectADeletedRecord() {
        val record=Record.create(RecordType.MEAL).apply {json.put("name","已删除餐食")}
        scenario.onActivity {vm.save(record);vm.delete(record)}
        scenario.onActivity {assertThrows(IllegalArgumentException::class.java) {vm.save(record.copy())}}
        assertTrue(app.store.load().records.isEmpty())
    }
    @Test fun libraryEditorRestoresFavoriteAndExerciseDrafts() {
        compose.onNodeWithTag("tab-3").performClick()
        compose.onNodeWithText("记录与提醒").performClick()
        compose.onNodeWithText("常用餐食").performClick()
        compose.onNodeWithContentDescription("添加").performClick()
        field("餐食名称","保留的常用餐食");hideKeyboard();scenario.recreate()
        compose.onNodeWithContentDescription("餐食名称").assertTextContains("保留的常用餐食")
        compose.onNodeWithText("保存").performClick();compose.waitForIdle()
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("我的动作库").performClick();compose.onNodeWithContentDescription("添加").performClick()
        field("动作名称","保留的动作");hideKeyboard();scenario.recreate()
        compose.onNodeWithContentDescription("动作名称").assertTextContains("保留的动作")
        compose.onNodeWithText("保存").performClick();compose.waitForIdle()
        assertTrue(app.store.load().records.any {it.type==RecordType.EXERCISE && it.title=="保留的动作"})
    }
    @Test fun completedAppearanceAndScrollProfileWithPowerSaveFallback() {
        scenario.onActivity {vm.seedDemo()};compose.waitForIdle()
        screenshot("home-light")
        val times=java.util.Collections.synchronizedList(mutableListOf<Long>())
        val listener=android.view.Window.OnFrameMetricsAvailableListener {_,metrics,_ ->
            times.add(metrics.getMetric(android.view.FrameMetrics.TOTAL_DURATION))
        }
        scenario.onActivity {it.window.addOnFrameMetricsAvailableListener(listener,android.os.Handler(android.os.Looper.getMainLooper()))}
        repeat(3) {compose.onNode(hasScrollAction()).performTouchInput {swipeUp(startY=height*.7f,endY=height*.25f,durationMillis=350)};compose.waitForIdle()}
        repeat(3) {compose.onNode(hasScrollAction()).performTouchInput {swipeDown(startY=height*.25f,endY=height*.7f,durationMillis=350)};compose.waitForIdle()}
        scenario.onActivity {it.window.removeOnFrameMetricsAvailableListener(listener)}
        val frames=times.toList().filter {it>0}.sorted()
        assertTrue("Frame timing must be captured",frames.isNotEmpty())
        val renderer=androidx.test.platform.app.InstrumentationRegistry.getArguments().getString("renderer","unspecified")
        val profile=JSONObject().put("device","API ${android.os.Build.VERSION.SDK_INT} emulator / $renderer; not a physical-device benchmark")
            .put("frames",frames.size).put("p50Ms",frames[frames.size/2]/1_000_000.0)
            .put("p95Ms",frames[((frames.size-1)*.95).toInt()]/1_000_000.0).put("over16_7Ms",frames.count {it>16_700_000})
        java.io.File(app.filesDir,"parity-completed/frame-profile.json").writeText(profile.toString(2))
        compose.onNode(hasScrollAction()).performScrollToIndex(0)
        fun shell(command:String):String = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use {pfd -> java.io.FileInputStream(pfd.fileDescriptor).bufferedReader().readText()}
        try {
            shell("dumpsys battery unplug");shell("dumpsys battery set level 30");shell("cmd power set-mode 1")
            compose.waitUntil(5000) {(app.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager).isPowerSaveMode}
            // API31 power saving can suppress the next Choreographer draw that
            // Compose's Espresso barrier waits for even when the app is idle.
            // Request one frame and capture the device, without that test-only barrier.
            compose.mainClock.advanceTimeBy(64)
            scenario.onActivity {it.window.decorView.invalidate()}
            screenshot("home-power-save",awaitCompose=false)
        } finally {shell("cmd power set-mode 0");shell("dumpsys battery reset")}
        compose.onNodeWithTag("tab-3").performClick();screenshot("settings-light")
        scenario.onActivity {vm.personalize("dark","purple")}
        compose.onNodeWithTag("tab-0").performClick();screenshot("home-dark")
        compose.onNodeWithTag("tab-1").performClick();screenshot("trends-dark")
    }
    @Test fun largeTextChoicesWrapAndAllModesRemainReachable() {
        scenario.onActivity {it.setContent {LifeTheme {
            val density=LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density,2f)) {
                Column(Modifier.width(260.dp)) {ChoiceControl(MealScanMode.entries.map {it.name to it.title},MealScanMode.MEAL.name,{})}
            }
        }}}
        MealScanMode.entries.forEach {compose.onNodeWithText(it.title).assertIsDisplayed()}
        val first=compose.onNodeWithText("餐盘识别").fetchSemanticsNode().boundsInRoot
        val last=compose.onNodeWithText("配料表").fetchSemanticsNode().boundsInRoot
        assertTrue(last.top>=first.bottom)
        screenshot("large-text-choices")
    }
}
