package ltd.apsonchian.liferecord

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.providerConfig
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule val compose = createEmptyComposeRule()
    private lateinit var app: LifeRecordApplication
    private lateinit var before: Snapshot
    private lateinit var scenario: ActivityScenario<MainActivity>
    private var onboarding = ""
    private var conversations = "[]"
    private var acknowledgements = "[]"
    private var report = ""
    @Before fun setup() {
        app = ApplicationProvider.getApplicationContext()
        before = app.store.load(); onboarding = app.store.get("onboarded")
        conversations = app.store.get("conversations", "[]"); app.store.set("conversations", "[]")
        acknowledgements=app.store.get("recordQuality.acknowledged","[]");report=app.store.get("weeklyReport")
        app.store.set("recordQuality.acknowledged","[]");app.store.set("weeklyReport","")
        app.store.commit(Snapshot(emptyList(), defaultProfile(), emptyList()))
        app.store.set("onboarded", "yes")
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }
    @After fun restore() {
        scenario.close(); app.store.commit(before); app.store.set("onboarded", onboarding); app.store.set("conversations", conversations)
        app.store.set("recordQuality.acknowledged",acknowledgements);app.store.set("weeklyReport",report)
    }
    @Test fun manualMealSaveAndDeleteUsesSamePersistentRecord() {
        compose.onNodeWithContentDescription("添加记录").performClick()
        compose.onAllNodesWithText("记一餐").onLast().performClick()
        compose.onAllNodes(hasSetTextAction())[0].performTextReplacement("Android test lunch")
        compose.onAllNodes(hasSetTextAction())[1].performTextReplacement("500")
        compose.onAllNodes(hasSetTextAction())[2].performTextReplacement("30")
        compose.onAllNodes(hasSetTextAction())[3].performTextReplacement("60")
        compose.onAllNodes(hasSetTextAction())[4].performTextReplacement("15")
        compose.onAllNodes(hasSetTextAction())[5].performTextReplacement("4")
        compose.onNodeWithText("保存").performClick()
        compose.waitForIdle()
        val saved = app.store.load().records.single { it.type == RecordType.MEAL }
        assertEquals("Android test lunch", saved.title)
        assertEquals(500.0, saved.json.getDouble("calories"), 0.0)
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("Android test lunch"))
        compose.onNodeWithText("Android test lunch").performClick()
        compose.onAllNodes(hasScrollAction()).onLast().performScrollToNode(hasText("删除这条记录"))
        compose.onNodeWithText("删除这条记录").performClick()
        compose.onNodeWithText("删除", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        val deleted = app.store.load()
        assertTrue(deleted.records.none { it.id == saved.id })
        assertTrue(deleted.deletions.any { it.getString("id") == saved.id })
    }
    @Test fun trainingCanStartFinishAndNavigateEveryTab() {
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("开始训练"))
        // The floating bar intentionally overlays the bottom of the scroll viewport.
        compose.onNode(hasScrollAction()).performTouchInput { swipeUp(startY=height*.8f,endY=height*.5f,durationMillis=250) }
        compose.onNodeWithText("开始训练").performClick()
        compose.waitForIdle()
        val active = app.store.load().records.single { it.type == RecordType.WORKOUT }
        assertTrue(active.json.isNull("endDate"))
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("结束训练", substring = true))
        compose.onNode(hasText("结束训练", substring = true)).performClick()
        compose.waitForIdle()
        compose.waitUntil(3000) { app.store.load().records.single { it.id == active.id }.json.opt("endDate") != org.json.JSONObject.NULL }
        val finished = app.store.load().records.single { it.id == active.id }
        assertTrue(finished.json.getDouble("endDate") >= finished.date)
        compose.onNodeWithText("训练部位").assertExists()
        compose.onNodeWithText("取消").performClick()
        compose.onNodeWithTag("tab-1").performClick()
        compose.onNodeWithText("回顾训练与身体变化").assertExists()
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNodeWithText("你的 AI 教练").assertExists()
        compose.onNodeWithTag("tab-3").performClick()
        compose.onNodeWithText("偏好与个人目标").assertExists()
    }
    @Test fun tabsRetainRangeSearchAndUnsentCoachDraft() {
        compose.onNodeWithTag("tab-1").performClick()
        compose.onNodeWithText("7 天").performClick()
        compose.onNodeWithContentDescription("查看全部数据详情").performClick()
        compose.onNode(hasSetTextAction()).performTextReplacement("retained search")
        hideKeyboard()
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNode(hasSetTextAction()).performTextReplacement("draft retained without sending")
        scenario.onActivity { activity ->
            (activity.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).hideSoftInputFromWindow(activity.window.decorView.windowToken, 0)
        }
        compose.waitUntil(3000) { compose.onAllNodesWithTag("tab-0").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("tab-0").performClick()
        compose.onNodeWithTag("tab-1").performClick()
        compose.onNode(hasSetTextAction()).assertTextContains("retained search")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("7 天").assertIsSelected()
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNode(hasSetTextAction()).assertTextContains("draft retained without sending")
        assertEquals("[]", app.store.get("conversations", "[]"))
    }
    @Test fun insightPrefillsCoachWithoutSendingToAI() {
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("今日提示"))
        compose.onNodeWithText("今日提示").performClick()
        compose.onNode(hasSetTextAction()).assertTextContains("给出可执行的下一步建议", substring=true)
        compose.onNodeWithTag("tab-2").assertIsSelected()
        assertEquals("[]", app.store.get("conversations", "[]"))
    }
    @Test fun glassNavigationCanScrubToAnotherTab() {
        compose.onNodeWithTag("glass-navigation").performTouchInput {
            swipe(androidx.compose.ui.geometry.Offset(width*.10f, height*.5f), androidx.compose.ui.geometry.Offset(width*.91f, height*.5f), 350)
        }
        compose.onNodeWithTag("tab-3").assertIsSelected()
        compose.onNodeWithText("偏好与个人目标").assertExists()
    }

    private fun hideKeyboard() {
        scenario.onActivity { activity ->
            (activity.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).hideSoftInputFromWindow(activity.window.decorView.windowToken, 0)
        }
        compose.waitUntil(3000) { compose.onAllNodesWithTag("tab-0").fetchSemanticsNodes().isNotEmpty() }
    }
    private fun model(block:(AppViewModel)->Unit) { scenario.onActivity { block(ViewModelProvider(it)[AppViewModel::class.java]) };compose.waitForIdle() }
    private fun expose(text:String) {
        compose.onNode(hasScrollAction()).performScrollToNode(hasText(text))
        val target=compose.onNodeWithText(text).fetchSemanticsNode().boundsInRoot
        val bar=compose.onNodeWithTag("glass-navigation").fetchSemanticsNode().boundsInRoot
        if(target.bottom>bar.top) compose.onNode(hasScrollAction()).performTouchInput { swipeUp(startY=height*.8f,endY=height*.5f,durationMillis=200) }
    }
    @Test fun qualityConfirmationPreservesRecordsAndExpiresAfterEdit() {
        scenario.close()
        val first=Record.create(RecordType.MEAL,now()-3600).apply { json.put("name","QA lunch");json.put("calories",500);json.put("protein",30);json.put("carbs",60);json.put("fat",15);json.put("fiber",4) }
        val second=Record.create(RecordType.MEAL,first.date+60).apply { listOf("name","calories","protein","carbs","fat","fiber").forEach { json.put(it,first.json.get(it)) } }
        app.store.commit(Snapshot(listOf(first,second),defaultProfile(),emptyList()))
        scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("tab-1").performClick();expose("记录质量检查")
        compose.onNodeWithText("记录质量检查").performClick()
        capture("quality-review")
        expose("确认记录无误");compose.onNodeWithText("确认记录无误").performClick()
        compose.onNodeWithText("确认无误",useUnmergedTree=true).performClick()
        compose.onNodeWithText("已确认").performClick()
        compose.onNodeWithText("重新核对").assertExists()
        assertEquals(setOf(first.id,second.id),app.store.load().records.map { it.id }.toSet())
        assertEquals(first.updated,app.store.load().records.first { it.id==first.id }.updated,0.0)
        model { it.save(first.copy().apply { json.put("note","checked amount") }) }
        compose.onNodeWithText("待核对").performClick()
        compose.onNodeWithText("确认记录无误").assertExists()
    }
    @Test fun coachUsesLeftDrawerAndSwitchesConversations() {
        model { vm -> vm.newConversation();vm.send("",emptyList()) }
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNodeWithContentDescription("对话列表").performClick()
        compose.onNodeWithContentDescription("关闭对话列表").assertExists()
        capture("coach-drawer")
        compose.onNodeWithContentDescription("新建对话").performClick()
        var ids=listOf<String>();model { ids=it.conversations.value.map { c -> c.getString("id") } }
        assertEquals(2,ids.size)
        compose.onNodeWithContentDescription("对话列表").performClick()
        compose.onAllNodesWithText("新的对话").onLast().performClick()
        model { assertEquals(ids.last(),it.selectedConversation.value) }
    }
    @Test fun chatPhotoDraftSurvivesTabsAndSentPhotoSurvivesRestart() {
        val bitmap=android.graphics.Bitmap.createBitmap(12,8,android.graphics.Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.BLUE) }
        val bytes=java.io.ByteArrayOutputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG,90,it);it.toByteArray() };bitmap.recycle()
        model { it.draftPhotos.value=listOf(bytes);it.config.value=providerConfig("自定义").put("model","") }
        compose.onNodeWithTag("tab-2").performClick();compose.onNodeWithText("已选 1 张照片").assertExists()
        compose.onNodeWithTag("tab-0").performClick();compose.onNodeWithTag("tab-2").performClick();compose.onNodeWithText("已选 1 张照片").assertExists()
        compose.onNode(hasSetTextAction()).performTextReplacement("photo persistence QA")
        compose.onNodeWithContentDescription("发送").performClick();hideKeyboard()
        compose.waitUntil(5000) { org.json.JSONArray(app.store.get("conversations","[]")).objects().firstOrNull()?.getJSONArray("messages")?.length()==2 }
        val chat=org.json.JSONArray(app.store.get("conversations")).getJSONObject(0)
        val name=chat.getJSONArray("messages").getJSONObject(0).getJSONArray("localPhotoFiles").getString(0)
        assertArrayEquals(bytes,app.photos.chat(name))
        scenario.close();scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("tab-2").performClick()
        compose.waitUntil(5000) { compose.onAllNodesWithContentDescription("照片").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("照片").performClick()
        compose.onNodeWithText("保存到相册").assertExists()
        compose.onNodeWithTag("photo-viewer").performTouchInput { doubleClick(center) }
        compose.onNodeWithTag("photo-viewer").performTouchInput { swipeDown(startY=height*.35f,endY=height*.65f,durationMillis=250) }
        compose.onNodeWithContentDescription("关闭照片").assertExists()
        compose.onNodeWithTag("photo-viewer").performTouchInput { doubleClick(center) }
        compose.onNodeWithTag("photo-viewer").performTouchInput { swipeDown(startY=height*.35f,endY=height*.65f,durationMillis=250) }
        compose.onNodeWithContentDescription("关闭照片").assertDoesNotExist()
        model { it.deleteConversation(chat.getString("id")) }
        assertThrows(java.io.FileNotFoundException::class.java) { app.photos.chat(name) }
    }
    @Test fun savedWeeklyReportOpensInsideTrendsAndRetainsPosition() {
        scenario.close()
        app.store.set("weeklyReport",org.json.JSONObject().put("text","# 目标距离\nQA weekly report").put("generatedAt",now()).toString())
        scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("tab-1").performClick();expose("阅读本周报告")
        compose.onNodeWithText("阅读本周报告").performClick()
        capture("report-open")
        compose.onNodeWithText("AI 周报").assertExists();compose.onNodeWithText("QA weekly report").assertExists()
        capture("weekly-report")
        compose.onNodeWithTag("tab-1").assertIsSelected()
        compose.onNodeWithTag("tab-2").performClick();compose.onNodeWithTag("tab-1").performClick()
        compose.onNodeWithText("QA weekly report").assertExists()
        compose.onNodeWithContentDescription("返回").performClick()
        assertEquals("[]",app.store.get("conversations","[]"))
    }

    @Test fun measurementDetailFiltersPeriodAndRecalculatesSmoothTrend() {
        scenario.close()
        val records=(1L..8L).flatMap { offset ->
            val day=java.time.LocalDate.now().minusDays(offset)
            listOf(8 to 70.0+offset*.1,18 to 72.0+offset*.1).map { (hour,weight) ->
                Record.create(RecordType.BODY,day.epochAt(java.time.LocalTime.of(hour,0))).apply { json.put("weight",weight);json.put("bodyFat",22.0+offset*.05) }
            }
        }
        app.store.commit(Snapshot(records,defaultProfile(),emptyList()))
        scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("tab-1").performClick();expose("体重趋势")
        capture("trends-light")
        compose.onNodeWithTag("weight-detail").performClick()
        capture("measurement-open")
        compose.onNodeWithText("体重详情").assertExists()
        compose.onNodeWithText("早上",useUnmergedTree=true).performClick()
        compose.onNodeWithText("早上").assertIsSelected()
        compose.onNode(isToggleable()).performClick()
        compose.onNodeWithText("每日中位数 · 指数平滑").assertExists()
        compose.onNodeWithContentDescription("上一日测量").performClick()
        compose.onNode(hasText("次测量",substring=true)).assertExists()
        capture("measurement-detail")
    }
    private fun capture(name:String) {
        val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        if(android.os.Build.VERSION.SDK_INT<29 || androidx.test.platform.app.InstrumentationRegistry.getArguments().getString("captureScreenshots")!="true") return
        compose.waitForIdle()
        val bitmap=instrumentation.uiAutomation.takeScreenshot() ?: error("Screenshot unavailable")
        val values=android.content.ContentValues().apply {
            put(android.provider.MediaStore.Downloads.DISPLAY_NAME,"$name.png")
            put(android.provider.MediaStore.Downloads.MIME_TYPE,"image/png")
            put(android.provider.MediaStore.Downloads.RELATIVE_PATH,"Download/LifeRecordQA")
            put(android.provider.MediaStore.Downloads.IS_PENDING,1)
        }
        val resolver=app.contentResolver
        val uri=resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,values)!!
        resolver.openOutputStream(uri)!!.use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };bitmap.recycle()
        resolver.update(uri,android.content.ContentValues().apply { put(android.provider.MediaStore.Downloads.IS_PENDING,0) },null,null)
    }
}
