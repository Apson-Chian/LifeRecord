package ltd.apsonchian.liferecord

import androidx.activity.compose.setContent
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
    private var identity = "{}"
    private var aiConfig = ""
    private var appearance = "system"
    private var accent = "purple"
    private var partCatalog = ""
    @Before fun setup() {
        app = ApplicationProvider.getApplicationContext()
        partCatalog=app.store.get("workout.bodyPartCatalog");app.store.set("workout.bodyPartCatalog",org.json.JSONArray(parts).toString())
        appearance=app.store.get("appearance","system");accent=app.store.get("accent","purple")
        app.store.set("appearance","system");app.store.set("accent","purple")
        identity=app.store.get("coach.identity","{}");aiConfig=app.store.get("aiConfig")
        app.store.set("coach.identity","{}");app.store.set("aiConfig",providerConfig("DeepSeek").toString())
        before = app.store.load(); onboarding = app.store.get("onboarded")
        conversations = app.store.get("conversations", "[]"); app.store.set("conversations", "[]")
        acknowledgements=app.store.get("recordQuality.acknowledged","[]");report=app.store.get("weeklyReport")
        app.store.set("recordQuality.acknowledged","[]");app.store.set("weeklyReport","")
        app.store.commit(Snapshot(emptyList(), defaultProfile(), emptyList()))
        app.store.set("onboarded", "yes")
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }
    @After fun restore() {
        if(android.os.Build.VERSION.SDK_INT>=31) (app.getSystemService(android.content.Context.UI_MODE_SERVICE) as android.app.UiModeManager).setApplicationNightMode(android.app.UiModeManager.MODE_NIGHT_AUTO)
        scenario.close(); app.store.commit(before); app.store.set("onboarded", onboarding); app.store.set("conversations", conversations)
        app.store.set("recordQuality.acknowledged",acknowledgements);app.store.set("weeklyReport",report)
        app.store.set("coach.identity",identity);app.store.set("aiConfig",aiConfig.ifBlank {providerConfig("DeepSeek").toString()})
        app.store.set("appearance",appearance);app.store.set("accent",accent)
        app.store.set("workout.bodyPartCatalog",partCatalog.ifBlank {org.json.JSONArray(parts).toString()})
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
        compose.onNodeWithContentDescription("回顾训练与身体变化").assertExists()
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNodeWithTag("coach-title").assertExists()
        compose.onNodeWithTag("tab-3").performClick()
        compose.onNodeWithContentDescription("偏好与个人目标").assertExists()
    }
    @Test fun tabsRetainRangeSearchAndUnsentCoachDraft() {
        compose.onNodeWithTag("tab-1").performClick()
        compose.onNodeWithText("近 7 天").performClick()
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
        compose.onNodeWithText("近 7 天").assertIsSelected()
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
        compose.onNodeWithContentDescription("偏好与个人目标").assertExists()
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
    @Test fun multipleFavoritesFillCombinedMealAndPhotos() {
        val bitmap=android.graphics.Bitmap.createBitmap(12,8,android.graphics.Bitmap.Config.ARGB_8888).apply {eraseColor(android.graphics.Color.GREEN)}
        val bytes=java.io.ByteArrayOutputStream().use {bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG,90,it);it.toByteArray()};bitmap.recycle()
        val photo=app.photos.save(bytes)
        try {
            val milk=Record.create(RecordType.FAVORITE).apply {json.put("name","QA 牛奶").put("portion","250 ml").put("calories",145).put("protein",8).put("carbs",12).put("fat",7).put("fiber",0).put("localPhotoFiles",org.json.JSONArray().put(photo))}
            val bread=Record.create(RecordType.FAVORITE).apply {json.put("name","QA 面包").put("portion","2片").put("calories",180).put("protein",6).put("carbs",30).put("fat",4).put("fiber",3)}
            model {it.save(milk);it.save(bread)}
            compose.onNodeWithContentDescription("添加记录").performClick();compose.onAllNodesWithText("记一餐").onLast().performClick()
            compose.onNodeWithText("常用餐食").performClick()
            compose.onNodeWithText("QA 牛奶").performClick();compose.onNodeWithText("QA 面包").performClick()
            compose.onNodeWithText("填入 2 项").performClick()
            compose.waitUntil(5000) {compose.onAllNodesWithText("继续添加 · 已选 1 张").fetchSemanticsNodes().isNotEmpty()}
            // Reopen, deselect and reselect without duplicating nutrition or photos.
            compose.onNodeWithText("常用餐食").performClick();compose.onNodeWithText("QA 面包").performClick();compose.onNodeWithText("填入 1 项").assertExists()
            compose.onNodeWithText("QA 面包").performClick();compose.onNodeWithText("填入 2 项").performClick()
            compose.onNodeWithText("保存").performClick();compose.waitForIdle()
            val meal=app.store.load().records.single {it.type==RecordType.MEAL}
            assertEquals("QA 牛奶、QA 面包",meal.title);assertEquals(325.0,meal.json.getDouble("calories"),0.01)
            assertEquals(14.0,meal.json.getDouble("protein"),0.01);assertEquals(3.0,meal.json.getDouble("fiber"),0.01)
            assertEquals(1,meal.json.getJSONArray("localPhotoFiles").length())
            capture("multi-favorite-meal")
            meal.json.getJSONArray("localPhotoFiles").strings().forEach {app.photos.deleteLocal(it)}
        } finally {app.photos.deleteLocal(photo)}
    }
    @Test fun chatPhotoDraftSurvivesTabsAndSentPhotoSurvivesRestart() {
        val bitmap=android.graphics.Bitmap.createBitmap(12,8,android.graphics.Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.BLUE) }
        val bytes=java.io.ByteArrayOutputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG,90,it);it.toByteArray() };bitmap.recycle()
        model { it.draftPhotos.value=listOf(bytes,bytes);it.config.value=providerConfig("自定义").put("model","") }
        compose.onNodeWithTag("tab-2").performClick();compose.onNodeWithText("已选 2 张照片").assertExists()
        compose.onNodeWithTag("tab-0").performClick();compose.onNodeWithTag("tab-2").performClick();compose.onNodeWithText("已选 2 张照片").assertExists()
        compose.onNode(hasSetTextAction()).performTextReplacement("photo persistence QA")
        compose.onNodeWithContentDescription("发送").performClick();hideKeyboard()
        compose.waitUntil(5000) { org.json.JSONArray(app.store.get("conversations","[]")).objects().firstOrNull()?.getJSONArray("messages")?.objects()?.firstOrNull()?.optString("generationState")=="failed" }
        val chat=org.json.JSONArray(app.store.get("conversations")).getJSONObject(0)
        val name=chat.getJSONArray("messages").getJSONObject(0).getJSONArray("localPhotoFiles").getString(0)
        val other=chat.getJSONArray("messages").getJSONObject(0).getJSONArray("localPhotoFiles").getString(1)
        assertArrayEquals(bytes,app.photos.chat(name));assertArrayEquals(bytes,app.photos.chat(other))
        scenario.close();scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("tab-2").performClick()
        compose.waitUntil(5000) { compose.onAllNodesWithContentDescription("照片").fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodesWithContentDescription("照片").onFirst().performClick()
        compose.onNodeWithText("保存到相册").assertExists()
        compose.onNodeWithTag("photo-viewer").performTouchInput { doubleClick(center) }
        compose.onNodeWithTag("photo-viewer").performTouchInput { swipeDown(startY=height*.35f,endY=height*.65f,durationMillis=250) }
        compose.onNodeWithContentDescription("关闭照片").assertExists()
        compose.onNodeWithTag("photo-viewer").performTouchInput { doubleClick(center) }
        compose.onNodeWithTag("photo-viewer").performTouchInput { swipeDown(startY=height*.35f,endY=height*.65f,durationMillis=250) }
        compose.onNodeWithContentDescription("关闭照片").assertDoesNotExist()
        model { it.deleteConversation(chat.getString("id")) }
        assertThrows(java.io.FileNotFoundException::class.java) { app.photos.chat(name) }
        assertThrows(java.io.FileNotFoundException::class.java) { app.photos.chat(other) }
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
        compose.onNodeWithTag("tab-1").performClick();capture("trends-light")
        expose("体重趋势")
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
    @Test(timeout=45000) fun nativeLayoutDailyGoalsAndScreenshots() {
        scenario.close()
        val profile=defaultProfile().put("fitnessGoal","增肌").put("height",181).put("baselineWeight",64).put("targetWeight",72).put("weeklyWeightTarget",.25).put("calorieGoal",2600).put("proteinGoal",130).put("carbsGoal",340).put("fatGoal",70)
        val meals=listOf(
            listOf("早餐","燕麦鸡蛋牛奶碗",545,34,64,15,8,7),
            listOf("午餐","鸡胸肉糙米饭",780,56,88,19,7,12),
            listOf("晚餐","三文鱼藜麦沙拉",665,47,58,24,10,19),
            listOf("加餐","蛋白棒与香蕉",285,24,35,8,5,16)
        ).map {row -> Record.create(RecordType.MEAL,java.time.LocalDate.now().epochAt(java.time.LocalTime.of(row[7] as Int,0))).apply {
            json.put("kind",row[0]);json.put("name",row[1]);listOf("calories","protein","carbs","fat","fiber").forEachIndexed {i,key -> json.put(key,row[i+2])};json.put("isDemo",true)
        }}
        val body=Record.create(RecordType.BODY,java.time.LocalDate.now().epochAt(java.time.LocalTime.of(8,0))).apply {json.put("weight",65);json.put("bodyFat",14.3);json.put("isDemo",true)}
        app.store.commit(Snapshot(meals+body,profile,emptyList()))
        scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("page-title").assertExists()
        compose.onNodeWithContentDescription("今日营养圆环，用餐 4 次").assertExists()
        capture("today-light-1.3")
        compose.onNodeWithTag("tab-3").performClick()
        compose.onNodeWithText("个人与目标").assertExists()
        compose.onNodeWithText("记录与提醒").assertExists()
        compose.onNodeWithText("教练与 AI").assertExists()
        compose.onNodeWithText("每日目标").assertDoesNotExist()
        capture("settings-light-oct15")
        compose.onNodeWithText("个人与目标").performClick()
        compose.onNodeWithContentDescription("身高").assertExists()
        compose.onNode(hasScrollAction()).performScrollToNode(hasContentDescription("热量"))
        compose.onNodeWithContentDescription("热量").performTextReplacement("2500")
        hideKeyboard()
        capture("profile-light-oct15")
        compose.onNodeWithText("保存").performClick()
        compose.waitForIdle()
        assertEquals(2500.0,app.store.load().profile.getDouble("calorieGoal"),0.0)
        assertEquals(181.0,app.store.load().profile.getDouble("height"),0.0)
        compose.onNodeWithTag("tab-2").performClick()
        capture("coach-light-1.3")
        compose.onNode(hasSetTextAction()).performClick().performTextReplacement("键盘和导航测试")
        compose.waitUntil(5000) {compose.onAllNodesWithTag("glass-navigation").fetchSemanticsNodes().isEmpty()}
        compose.onNodeWithTag("glass-navigation").assertDoesNotExist()
        capture("coach-keyboard-1.3")
        hideKeyboard()
        // Exercise the app's actual theme setting without restarting the instrumentation Activity.
        model {it.personalize("dark","purple")};capture("coach-dark-beta2")
        scenario.onActivity {assertFalse(androidx.core.view.WindowCompat.getInsetsController(it.window,it.window.decorView).isAppearanceLightStatusBars)}
        compose.onNodeWithTag("tab-0").performClick();capture("today-dark-beta2")
        compose.onNodeWithTag("tab-3").performClick();capture("settings-dark-beta2")
    }
    @Test fun coachAlwaysOpensAtLatestMessageIncludingEqualLengthConversationSwitches() {
        scenario.close()
        fun chat(id:String):org.json.JSONObject {
            val entries=org.json.JSONArray()
            repeat(32) { index -> entries.put(org.json.JSONObject().put("role",if(index%2==0) "user" else "assistant")
                .put("content",if(index==31) "LATEST-$id" else "Message-$id-$index\nHistorical conversation content with several lines.")) }
            return org.json.JSONObject().put("id",id).put("title","Thread-$id").put("messages",entries)
        }
        app.store.set("conversations",org.json.JSONArray().put(chat("A")).put(chat("B")).toString())
        scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNodeWithText("LATEST-A").assertIsDisplayed()
        compose.onNodeWithTag("coach-messages").performScrollToIndex(0)
        compose.onNodeWithText("Message-A-0",substring=true).assertIsDisplayed()
        compose.onNodeWithTag("tab-0").performClick()
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNodeWithText("LATEST-A").assertIsDisplayed()
        compose.onNodeWithContentDescription("对话列表").performClick()
        compose.onNodeWithText("Thread-B").performClick()
        compose.onNodeWithText("LATEST-B").assertIsDisplayed()
        capture("coach-latest-oct15")
    }
    @Test fun feedbackIsCompactAndOnlyExpandsDetailsOnRequest() {
        scenario.close()
        val points=listOf(6L,3L,1L).map { offset -> Record.create(RecordType.BODY,java.time.LocalDate.now().minusDays(offset).epochAt()).apply {json.put("weight",70.0+offset*.05)} }
        app.store.commit(Snapshot(points,defaultProfile(),emptyList()))
        scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("tab-1").performClick()
        expose("和教练复盘")
        compose.onNodeWithText("热量在目标 ±10% 内").assertDoesNotExist()
        capture("feedback-compact-oct15")
        compose.onNodeWithTag("feedback-details").performClick()
        expose("热量在目标 ±10% 内")
        compose.onNodeWithText("热量在目标 ±10% 内").assertExists()
    }

    @Test fun coachIdentityCanBeEditedCanceledAndSurvivesRelaunchWithoutBeingExported() {
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNodeWithContentDescription("自定义教练：AI 助手").performClick()
        compose.onNodeWithContentDescription("聊天 AI 名称").performTextReplacement("力量教练")
        androidx.test.espresso.Espresso.closeSoftKeyboard();capture("coach-profile-beta2")
        compose.onNodeWithText("保存").performClick()
        compose.onNodeWithTag("coach-title").assertTextEquals("力量教练")
        compose.onNodeWithContentDescription("自定义教练：力量教练").performClick()
        compose.onNodeWithContentDescription("聊天 AI 名称").performTextReplacement("尚未保存")
        androidx.test.espresso.Espresso.closeSoftKeyboard();compose.onNodeWithText("取消").performClick()
        compose.onNodeWithTag("coach-title").assertTextEquals("力量教练")
        val bitmap=android.graphics.Bitmap.createBitmap(16,16,android.graphics.Bitmap.Config.ARGB_8888).apply {eraseColor(android.graphics.Color.BLUE)}
        val avatar=java.io.ByteArrayOutputStream().use {bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG,90,it);it.toByteArray()};bitmap.recycle()
        model {it.saveCoachIdentity("力量教练",avatar)}
        model {assertFalse(it.export().contains("力量教练"))}
        scenario.close();scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNodeWithTag("coach-title").assertTextEquals("力量教练")
        model {assertArrayEquals(avatar,it.coachIdentity.value.avatar)}
        compose.onNodeWithTag("coach-write-toggle").performClick().assertIsOn()
        model {assertTrue(it.config.value.getBoolean("canWrite"))}
        capture("coach-identity-beta2")
    }
    @Test fun workoutCalendarNavigatesMonthsShowsCompleteDayAndOpensOriginalRecord() {
        scenario.close()
        val day=java.time.LocalDate.now().withDayOfMonth(12)
        val r=Record.create(RecordType.WORKOUT,day.epochAt(java.time.LocalTime.of(9,0))).apply {
            json.put("endDate",date+3600);json.put("bodyParts",org.json.JSONArray().put("背部"));json.put("note","月历训练检查")
            json.put("exercises",org.json.JSONArray().put(org.json.JSONObject().put("name","坐姿划船").put("sets",org.json.JSONArray().put(org.json.JSONObject().put("weight",40).put("reps",8)))))
        }
        app.store.commit(Snapshot(listOf(r),defaultProfile(),emptyList()))
        scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithTag("tab-1").performClick();expose("训练日历")
        compose.onNodeWithText("训练日历").performClick()
        compose.onNodeWithTag("workout-calendar").assertExists()
        compose.onNodeWithContentDescription("上个月").performClick()
        compose.onNodeWithTag("workout-month").assertTextEquals("${java.time.YearMonth.now().minusMonths(1).monthValue}月")
        compose.onNodeWithText("回到本月").performClick()
        capture("workout-calendar-beta2")
        compose.onNodeWithTag("workout-day-$day").performClick()
        compose.onNodeWithText("40 kg × 8 次",substring=true).assertExists()
        capture("workout-calendar-day-beta2")
        compose.onNodeWithText("月历训练检查",substring=true).performClick()
        compose.onNodeWithText("编辑训练").assertExists()
        compose.onNodeWithText("取消").performClick()
        assertEquals(r.id,app.store.load().records.single().id)
    }
    @Test fun coachWritesOnlyValidatedDataAndReportsActualPersistence() {
        model {vm ->
            val id=vm.newConversation();val before=vm.snapshot.value
            val action=org.json.JSONObject().put("type","add_meal").put("name","鸡胸饭").put("calories",600).put("protein",42)
            val reply=org.json.JSONObject().put("answer","餐食估算").put("actions",org.json.JSONArray().put(action))
            vm.acceptCoachReply(id,reply,before,"帮我记录",emptyList(),false)
            assertTrue(app.store.load().records.isEmpty())
            assertTrue(vm.conversations.value.first().getJSONArray("messages").getJSONObject(0).getString("content").startsWith("未保存"))
            val invalid=reply.copy().put("actions",org.json.JSONArray().put(action).put(org.json.JSONObject().put("type","delete_meal").put("recordID","missing")))
            assertThrows(IllegalStateException::class.java) {vm.acceptCoachReply(id,invalid,before,"帮我记录",emptyList(),true)}
            assertTrue(app.store.load().records.isEmpty())
            vm.acceptCoachReply(id,reply,before,"帮我记录",emptyList(),true)
            val saved=app.store.load().records.single()
            assertEquals("鸡胸饭",saved.title);assertEquals(600.0,saved.json.getDouble("calories"),0.0)
            assertTrue(vm.conversations.value.first().getJSONArray("messages").objects().last().getString("content").contains("已核验并执行"))
            assertThrows(IllegalArgumentException::class.java) {vm.acceptCoachReply(id,reply,before,"帮我记录",emptyList(),true)}
            assertEquals(1,app.store.load().records.size)
        }
    }
    @Test fun stoppingCoachKeepsQuestionAndDoesNotWriteRecords() {
        val started=java.util.concurrent.CountDownLatch(1);val release=java.util.concurrent.CountDownLatch(1)
        val client=okhttp3.OkHttpClient.Builder().addInterceptor {chain ->
            started.countDown();release.await(5,java.util.concurrent.TimeUnit.SECONDS)
            okhttp3.Response.Builder().request(chain.request()).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body(okhttp3.ResponseBody.create(null,"{\"choices\":[{\"message\":{\"content\":\"{\\\"answer\\\":\\\"已记录\\\",\\\"actions\\\":[]}\"}}]}" )).build()
        }.build()
        val vm=AppViewModel(app,ltd.apsonchian.liferecord.service.Network(client))
        val config=providerConfig("自定义").put("model","local-test").put("endpoint","https://coach-local-test.invalid/chat/completions")
        val keyScope=ltd.apsonchian.liferecord.service.apiScope(config)
        app.secrets.save(keyScope,"local-test-key")
        try {
            scenario.onActivity {vm.config.value=config;vm.send("帮我记录午餐")}
            val reached=started.await(5,java.util.concurrent.TimeUnit.SECONDS)
            assertTrue("Request did not reach the mock transport: ${app.store.get("conversations")}",reached)
            scenario.onActivity {vm.stopCoach()};release.countDown()
            compose.waitUntil(5000) {!vm.aiBusy.value}
        } finally {release.countDown();app.secrets.save(keyScope,"")}
        val messages=org.json.JSONArray(app.store.get("conversations")).getJSONObject(0).getJSONArray("messages").objects()
        assertEquals("帮我记录午餐",messages.first().getString("content"));assertEquals("stopped",messages.first().getString("generationState"));assertTrue(messages.first().getString("generationError").startsWith("已停止生成"));assertEquals(1,messages.count {it.getString("role")=="user"});assertTrue(app.store.load().records.isEmpty())
        assertTrue(vm.activeCoachTasks.value.isEmpty())
    }

    private fun partFixture()=Record.create(RecordType.WORKOUT,now()-7200).apply {
        json.put("endDate",date+3600);json.put("bodyParts",org.json.JSONArray().put("手臂"));json.put("note","二头、三头")
        json.put("exercises",org.json.JSONArray().put(org.json.JSONObject().put("name","弯举").put("bodyPart","手臂").put("sets",org.json.JSONArray().put(org.json.JSONObject().put("weight",20).put("reps",8)))))
    }
    @Test fun dedicatedPartManagerRenamesAllDataAndRemovalPreservesHistory() {
        val r=partFixture();val template=Record.create(RecordType.EXERCISE).apply {json.put("name","弯举");json.put("bodyPart","手臂")}
        model {it.save(r);it.save(template);it.savePartChoices(parts+"手臂")}
        compose.onNodeWithTag("tab-1").performClick()
        compose.onNodeWithContentDescription("查看训练详情").performClick()
        compose.onNodeWithText("按部位").performClick()
        capture("workout-parts-beta3")
        compose.onNodeWithText("管理训练部位").performClick()
        compose.onNodeWithTag("rename-part-手臂").performScrollTo().performClick()
        compose.onNodeWithContentDescription("部位名称").performTextReplacement("上肢")
        androidx.test.espresso.Espresso.closeSoftKeyboard()
        compose.onNodeWithText("保存").performClick()
        compose.waitForIdle()
        val saved=app.store.load().records.single {it.id==r.id}
        assertEquals(listOf("上肢"),WorkoutParts.of(saved));assertEquals(20,saved.json.getJSONArray("exercises").getJSONObject(0).getJSONArray("sets").getJSONObject(0).getInt("weight"))
        assertEquals("上肢",app.store.load().records.single {it.id==template.id}.json.getString("bodyPart"))
        compose.onNodeWithTag("remove-part-上肢").performScrollTo().performClick()
        assertEquals(listOf("上肢"),WorkoutParts.of(app.store.load().records.single {it.id==r.id}))
        assertFalse(org.json.JSONArray(app.store.get("workout.bodyPartCatalog")).strings().contains("上肢"))
        capture("workout-part-manager-beta3")
    }
    @Test fun partAssistantGeneratesPreviewWithoutWritingThenAppliesOnlyConfirmedLabels() {
        val r=partFixture();model {it.save(r)}
        val reply=org.json.JSONObject().put("answer","请核对这次手臂训练的细分部位").put("changes",org.json.JSONArray().put(org.json.JSONObject().put("id",r.id).put("bodyParts",org.json.JSONArray().put("二头").put("三头"))))
        val client=okhttp3.OkHttpClient.Builder().addInterceptor {chain ->
            val envelope=org.json.JSONObject().put("choices",org.json.JSONArray().put(org.json.JSONObject().put("message",org.json.JSONObject().put("content",reply.toString()))))
            okhttp3.Response.Builder().request(chain.request()).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK").body(okhttp3.ResponseBody.create(null,envelope.toString())).build()
        }.build()
        val vm=AppViewModel(app,ltd.apsonchian.liferecord.service.Network(client))
        val config=providerConfig("自定义").put("model","local-test").put("endpoint","https://parts-local-test.invalid/chat/completions").put("canWrite",true)
        val keyScope=ltd.apsonchian.liferecord.service.apiScope(config);app.secrets.save(keyScope,"local-test-key");vm.config.value=config
        try {
            scenario.onActivity {activity ->activity.setContent {ltd.apsonchian.liferecord.ui.LifeTheme {ltd.apsonchian.liferecord.ui.WorkoutPartAssistant(vm,setOf(r.id),"手臂",{},{})}}}
            compose.onNodeWithContentDescription("例如：把这条手臂训练改为二头、三头、小臂").performTextReplacement("把这次训练细分为二头和三头")
            androidx.test.espresso.Espresso.closeSoftKeyboard()
            compose.onNodeWithText("发送").performScrollTo().performClick()
            compose.waitUntil(5000) {compose.onAllNodesWithText("修改预览").fetchSemanticsNodes().isNotEmpty()}
            assertEquals(listOf("手臂"),WorkoutParts.of(app.store.load().records.single()))
            compose.onNodeWithText("应用 1 条修改").performScrollTo()
            capture("workout-part-preview-beta3")
            compose.onNodeWithText("应用 1 条修改").performClick()
            compose.waitUntil(5000) {WorkoutParts.of(app.store.load().records.single())==listOf("二头","三头")}
            assertEquals(r.date,app.store.load().records.single().date,0.0)
        } finally {app.secrets.save(keyScope,"")}
    }

    private fun capture(name:String) {
        val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        if(android.os.Build.VERSION.SDK_INT<29 || androidx.test.platform.app.InstrumentationRegistry.getArguments().getString("captureScreenshots")!="true") return
        compose.waitUntil(8000) {compose.onAllNodesWithTag("status-message").fetchSemanticsNodes().isEmpty()}
        compose.waitForIdle()
        // SurfaceFlinger presents Compose and RenderEffect layers after the semantics commit.
        android.os.SystemClock.sleep(400)
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
