package ltd.apsonchian.liferecord

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import ltd.apsonchian.liferecord.data.*
import org.json.JSONObject
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.time.*

@RunWith(AndroidJUnit4::class)
class GoalHistoryFlowTest {
    @get:Rule val compose=createEmptyComposeRule()
    private lateinit var app:IsolatedLifeRecordApplication
    private lateinit var scenario:ActivityScenario<MainActivity>
    private val today=LocalDate.now()
    @Before fun setup() {
        app=TestIsolation.app();app.store.clearAll();app.secrets.clear()
        app.store.set("onboarded","yes");app.store.set("appearance","light")
        val meals=(0L..2L).map {days ->Record.create(RecordType.MEAL,today.minusDays(days).epochAt(LocalTime.MIN)).apply {
            json.put("name","目标历史测试餐食").put("calories",2000.0).put("protein",100.0).put("carbs",250.0)
        }}
        app.store.commit(Snapshot(meals,defaultProfile(),emptyList()))
        scenario=ActivityScenario.launch(MainActivity::class.java)
    }
    @After fun close() {scenario.close();app.store.clearAll();app.secrets.clear();app.photos.clearAll()}
    private fun ring(protein:String,carbs:String="250") {
        compose.onNodeWithContentDescription("今日营养圆环，用餐 1 次").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription,
            "蛋白质 100 / $protein 克，碳水 250 / $carbs 克"))
    }
    private fun screenshot(name:String) {
        compose.waitForIdle();android.os.SystemClock.sleep(300)
        val folder=java.io.File(app.filesDir,"goal-history-screens").apply {mkdirs()}
        val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()!!
        java.io.File(folder,"$name.png").outputStream().use {bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
    }
    @Test fun savingNewTargetsKeepsYesterdaysRingClosedAcrossColdLaunch() {
        compose.onNodeWithContentDescription("前一天").performClick();ring("100")
        screenshot("yesterday-before")
        compose.onNodeWithTag("tab-3").performClick();compose.onNodeWithText("个人与目标").performClick()
        compose.onNodeWithContentDescription("蛋白质").performScrollTo().performClick().performTextReplacement("150")
        compose.onNodeWithContentDescription("碳水").performScrollTo().performClick().performTextReplacement("300")
        compose.onNodeWithText("保存").performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("tab-0").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithTag("tab-0").performClick();ring("100")
        screenshot("yesterday-after")
        compose.onNodeWithContentDescription("后一天").performClick();ring("150","300")
        screenshot("today-new-target")
        scenario.close();scenario=ActivityScenario.launch(MainActivity::class.java)
        compose.onNodeWithContentDescription("前一天").performClick();ring("100")
        assertEquals(2,GoalHistory.versions(app.store.load().profile).size)
        compose.onNodeWithTag("tab-3").performClick();compose.onNodeWithText("目标历史").performClick()
        compose.onNodeWithText("${today} 起生效").assertExists()
        screenshot("history-list")
        compose.onNodeWithContentDescription("返回").performClick()
        compose.onNodeWithText("个人与目标").performClick()
        compose.onNodeWithContentDescription("称呼").performClick().performTextReplacement("目标历史测试")
        compose.onNodeWithText("保存").performClick()
        compose.waitUntil(5000) {compose.onAllNodesWithTag("tab-0").fetchSemanticsNodes().isNotEmpty()}
        assertEquals("A name-only edit must not add a goal version",2,GoalHistory.versions(app.store.load().profile).size)
    }
    @Test fun anOlderOfflineProfileContributesHistoryWithoutReplacingTodaysTarget() {
        lateinit var model:AppViewModel
        scenario.onActivity {model=ViewModelProvider(it)[AppViewModel::class.java];model.saveProfile(model.snapshot.value.profile.copy().put("proteinGoal",150.0))}
        val yesterday=today.minusDays(1)
        val old=GoalHistory.changed(defaultProfile(),defaultProfile().put("proteinGoal",120.0),yesterday.epochAt(LocalTime.NOON),yesterday)
        val merged=Merge.apply(app.store.load(),JSONObject().put("settings",old))
        // Recreating an Activity intentionally retains its ViewModel. A new
        // Activity owner exercises loading the merged snapshot from disk.
        scenario.close();app.store.commit(merged);scenario=ActivityScenario.launch(MainActivity::class.java)
        ring("150")
        compose.onNodeWithContentDescription("前一天").performClick();ring("120")
        compose.onNodeWithContentDescription("前一天").performClick();ring("100")
        assertEquals(3,GoalHistory.versions(app.store.load().profile).size)
    }
    @Test fun editingTargetsFromHistoryUpdatesOnlyTheirOwnPeriodAndSurvivesRestart() {
        scenario.onActivity {ViewModelProvider(it)[AppViewModel::class.java].let {vm ->vm.saveProfile(vm.snapshot.value.profile.copy().put("proteinGoal",150.0))}}
        compose.onNodeWithTag("tab-3").performClick();compose.onNodeWithText("目标历史").performClick()
        compose.onNodeWithContentDescription("编辑目标 $today").performScrollTo().performClick()
        compose.onNodeWithContentDescription("蛋白质").performScrollTo().performClick().performTextReplacement("120")
        compose.onNodeWithText("保存").performClick()
        compose.onNodeWithText("热量 2000 kcal · 蛋白质 120 g").assertExists()
        screenshot("corrected-history")
        compose.onNodeWithContentDescription("编辑目标 1970-01-01").performScrollTo().performClick()
        compose.onNodeWithContentDescription("蛋白质").performScrollTo().performClick().performTextReplacement("90")
        compose.onNodeWithText("保存").performClick()
        compose.onNodeWithContentDescription("返回").performClick();compose.onNodeWithTag("tab-0").performClick();ring("120")
        compose.onNodeWithContentDescription("前一天").performClick();ring("90")
        screenshot("corrected-yesterday")
        scenario.close();scenario=ActivityScenario.launch(MainActivity::class.java);ring("120")
        compose.onNodeWithContentDescription("前一天").performClick();ring("90")
        assertEquals(2,GoalHistory.versions(app.store.load().profile).size)
    }
    @Test fun correctingEffectiveDateWithTheNativePickerDoesNotLeaveAnOldVersion() {
        scenario.onActivity {ViewModelProvider(it)[AppViewModel::class.java].let {vm ->vm.saveProfile(vm.snapshot.value.profile.copy().put("proteinGoal",150.0))}}
        compose.onNodeWithTag("tab-3").performClick();compose.onNodeWithText("目标历史").performClick()
        compose.onNodeWithContentDescription("编辑目标 $today").performScrollTo().performClick()
        compose.onNodeWithContentDescription("生效日期").performClick()
        val yesterday=today.minusDays(1)
        androidx.test.espresso.Espresso.onView(androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom(android.widget.DatePicker::class.java)).perform(object:androidx.test.espresso.ViewAction {
            override fun getConstraints()=androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom(android.widget.DatePicker::class.java)
            override fun getDescription()="Choose the previous civil day in the native date picker"
            override fun perform(ui:androidx.test.espresso.UiController,view:android.view.View) {(view as android.widget.DatePicker).updateDate(yesterday.year,yesterday.monthValue-1,yesterday.dayOfMonth);ui.loopMainThreadUntilIdle()}
        })
        androidx.test.espresso.Espresso.onView(androidx.test.espresso.matcher.ViewMatchers.withId(android.R.id.button1)).perform(androidx.test.espresso.action.ViewActions.click())
        compose.onNodeWithText("生效日期：$yesterday").assertExists()
        screenshot("correction-editor")
        compose.onNodeWithText("保存").performClick()
        compose.onNodeWithText("${yesterday} 起生效").assertExists()
        compose.onNodeWithText("${today} 起生效").assertDoesNotExist()
        compose.onNodeWithContentDescription("返回").performClick();compose.onNodeWithTag("tab-0").performClick()
        compose.onNodeWithContentDescription("前一天").performClick();ring("150")
        compose.onNodeWithContentDescription("前一天").performClick();ring("100")
        assertEquals(2,GoalHistory.versions(app.store.load().profile).size)
    }
}
