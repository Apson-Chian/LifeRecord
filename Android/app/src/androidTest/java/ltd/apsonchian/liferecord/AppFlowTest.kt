package ltd.apsonchian.liferecord

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import ltd.apsonchian.liferecord.data.*
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
    @Before fun setup() {
        app = ApplicationProvider.getApplicationContext()
        before = app.store.load(); onboarding = app.store.get("onboarded")
        conversations = app.store.get("conversations", "[]"); app.store.set("conversations", "[]")
        app.store.commit(Snapshot(emptyList(), defaultProfile(), emptyList()))
        app.store.set("onboarded", "yes")
        scenario = ActivityScenario.launch(MainActivity::class.java)
    }
    @After fun restore() {
        scenario.close(); app.store.commit(before); app.store.set("onboarded", onboarding); app.store.set("conversations", conversations)
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
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNode(hasSetTextAction()).performTextReplacement("draft retained without sending")
        scenario.onActivity { activity ->
            (activity.getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).hideSoftInputFromWindow(activity.window.decorView.windowToken, 0)
        }
        compose.waitUntil(3000) { compose.onAllNodesWithTag("tab-0").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("tab-0").performClick()
        compose.onNodeWithTag("tab-1").performClick()
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
}
