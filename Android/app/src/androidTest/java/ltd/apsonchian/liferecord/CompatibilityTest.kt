package ltd.apsonchian.liferecord

import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.*
import ltd.apsonchian.liferecord.ui.LifeRecordApp
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class CompatibilityTest {
    @get:Rule val compose=createEmptyComposeRule()
    private lateinit var app:IsolatedLifeRecordApplication
    private lateinit var scenario:ActivityScenario<MainActivity>
    private lateinit var vm:AppViewModel
    @Before fun setup() {
        app=TestIsolation.app();app.store.clearAll();app.secrets.clear()
        app.store.set("onboarded","yes");app.store.set("appearance","light")
        scenario=ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity {vm=ViewModelProvider(it)[AppViewModel::class.java]}
    }
    @After fun close() {scenario.close();app.store.clearAll();app.secrets.clear();app.photos.clearAll()}
    private fun keyboard(visible:Boolean) {
        compose.waitUntil(8000) {
            var result=false
            scenario.onActivity {result=ViewCompat.getRootWindowInsets(it.window.decorView)?.isVisible(WindowInsetsCompat.Type.ime())==true}
            result==visible
        }
        compose.waitForIdle()
    }
    private fun screenshot(name:String) {
        compose.waitForIdle();android.os.SystemClock.sleep(300)
        val folder=java.io.File(app.filesDir,"compatibility-screens").apply {mkdirs()}
        val bitmap=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()!!
        java.io.File(folder,"$name.png").outputStream().use {bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
    }
    @Test fun coachBlankTapDismissesKeyboardWithoutSendingOrLosingDraft() {
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNode(hasSetTextAction()).performClick().performTextInput("保留这份草稿")
        keyboard(true)
        compose.onNodeWithTag("coach-messages").performTouchInput {click(Offset(width-2f,height*.5f))}
        keyboard(false)
        compose.onNode(hasSetTextAction()).assertTextContains("保留这份草稿")
        compose.onNodeWithTag("glass-navigation").assertExists()
        assertTrue(vm.conversations.value.isEmpty())
        screenshot("coach-keyboard-dismissed")
    }
    @Test fun formBlankTapDismissesKeyboardAndFieldsStillReceiveFocus() {
        compose.onNodeWithContentDescription("添加记录").performClick()
        compose.onAllNodesWithText("记一餐").onLast().performClick()
        compose.onNodeWithContentDescription("餐食名称").performClick().performTextInput("没有丢失")
        keyboard(true)
        compose.onNodeWithText("餐食名称").performTouchInput {click()}
        keyboard(false)
        compose.onNodeWithContentDescription("餐食名称").assertTextContains("没有丢失")
        screenshot("form-keyboard-dismissed")
        compose.onNodeWithContentDescription("热量 kcal").performScrollTo().performClick()
        keyboard(true)
    }
    @Test fun coachReceivesExamplesButCannotExecuteTheirActions() {
        val sent=AtomicReference<JSONObject>()
        val network=Network(OkHttpClient.Builder().addInterceptor {chain ->
            val buffer=okio.Buffer();chain.request().body!!.writeTo(buffer);sent.set(JSONObject(buffer.readUtf8()))
            val reply=JSONObject().put("answer","已添加").put("actions",JSONArray().put(JSONObject().put("type","add_meal").put("name","不应保存")))
            val result=JSONObject().put("choices",JSONArray().put(JSONObject().put("message",JSONObject().put("content",reply.toString()))))
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("fixture").body(result.toString().toResponseBody("application/json".toMediaType())).build()
        }.build())
        lateinit var model:AppViewModel
        var count=0
        scenario.onActivity {
            model=AppViewModel(app,network);model.seedDemo();count=model.snapshot.value.records.size
            model.config.value=providerConfig("自定义").put("endpoint","https://fixture.invalid/chat/completions").put("auth","Bearer").put("model","fixture").put("canWrite",true)
            app.secrets.save(apiScope(model.config.value),"fixture-local-only")
            model.send("帮我解读示例并添加一餐")
        }
        compose.waitUntil(10000) {sent.get()!=null && !model.aiBusy.value}
        val system=sent.get().getJSONArray("messages").getJSONObject(0).getString("content")
        assertTrue(system.contains("synthetic_examples"));assertTrue(system.contains("哑铃卧推"));assertTrue(system.contains("localDateTime"))
        assertEquals(count,model.snapshot.value.records.size)
        val answer=model.conversations.value.first {it.getString("id")==model.selectedConversation.value}.getJSONArray("messages").objects().last().getString("content")
        assertTrue(answer.contains("只读"));assertFalse(answer.contains("已添加"))
        assertEquals(0,JSONObject(model.export()).getJSONArray("favorites").length())
        assertEquals(0,JSONObject(model.export()).getJSONArray("exerciseTemplates").length())
    }
    @Test fun demoGoalsAndDataScopeAreVisibleWithoutChangingPersonalProfile() {
        val protein=vm.snapshot.value.profile.getDouble("proteinGoal")
        scenario.onActivity {vm.seedDemo()}
        compose.onNodeWithTag("tab-2").performClick()
        compose.onNodeWithTag("coach-data-scope").performClick()
        compose.onNodeWithText("AI 可以看到什么").assertIsDisplayed()
        compose.onNodeWithText("当前使用合成示例与示例目标；不代表你的身体情况，不执行记录修改。").assertIsDisplayed()
        assertEquals(protein,vm.snapshot.value.profile.getDouble("proteinGoal"),0.0)
        screenshot("coach-data-scope")
        compose.onNodeWithText("开始真实记录对话").performClick()
        compose.onNodeWithTag("coach-write-toggle").assertIsEnabled()
        compose.onNodeWithText("数据范围 · 全部本机真实记录").assertIsDisplayed()
    }
    @Test fun conversationLayoutKeepsComposerReachableAtDefaultAndLargeText() {
        val font=mutableFloatStateOf(1f)
        val id="typography-fixture"
        scenario.onActivity {activity ->
            vm.conversations.value=listOf(JSONObject().put("id",id).put("title","饮食与训练回顾").put("messages",JSONArray().put(
                JSONObject().put("id","u").put("role","user").put("content","请帮我回顾今天的记录。")
            ).put(JSONObject().put("id","a").put("role","assistant").put("content","## 今日记录回顾\n\n今天记录了 **3 餐**、一次身体测量和一组训练。\n\n- 饮食：按已保存的营养与份量核对。\n- 训练：可以查看动作、重量和每组次数。\n\n缺少记录的部分保持为空，不按零计算。"))))
            vm.selectedConversation.value=id
            activity.setContent {
                val density=LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density,font.floatValue)) {LifeRecordApp(vm)}
            }
        }
        compose.onNodeWithTag("tab-2").performClick()
        fun verify() {
            val composer=compose.onNodeWithTag("coach-composer").fetchSemanticsNode().boundsInRoot
            val nav=compose.onNodeWithTag("glass-navigation").fetchSemanticsNode().boundsInRoot
            val messages=compose.onNodeWithTag("coach-messages").fetchSemanticsNode().boundsInRoot
            val reply=compose.onNodeWithTag("coach-message-a").fetchSemanticsNode().boundsInRoot
            assertTrue("Input above navigation",composer.bottom<=nav.top+2)
            assertTrue("Conversation has a viewport",messages.height>80)
            assertTrue("Latest reply remains near the composer",messages.bottom-reply.bottom in 0f..120f)
            compose.onNode(hasSetTextAction()).assertIsDisplayed()
            compose.onNodeWithContentDescription("发送").assertIsDisplayed()
        }
        verify();screenshot("coach-conversation")
        compose.runOnIdle {font.floatValue=1.8f;vm.personalize("dark","purple")}
        verify();screenshot("coach-large-text-dark")
    }
}
