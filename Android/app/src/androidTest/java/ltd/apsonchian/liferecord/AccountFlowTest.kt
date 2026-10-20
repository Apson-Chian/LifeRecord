package ltd.apsonchian.liferecord

import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.syncScope
import ltd.apsonchian.liferecord.ui.LifeRecordApp
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountFlowTest {
    @get:Rule val compose=createEmptyComposeRule()
    private lateinit var app:IsolatedLifeRecordApplication
    private lateinit var scenario:ActivityScenario<MainActivity>
    private lateinit var vm:AppViewModel
    private val base=IsolatedLifeRecordApplication.BASE
    @Before fun setup() {
        app=TestIsolation.app()
        app.store.clearAll();app.secrets.clear();app.transport.accountFixtures=true
        app.store.set("sync.base",base);app.store.set("onboarded","yes")
        scenario=ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity {vm=ViewModelProvider(it)[AppViewModel::class.java]}
    }
    @After fun cleanup() {
        scenario.close();app.store.clearAll();app.secrets.clear();app.transport.accountFixtures=false
    }
    private fun connect(username:String="fixture.user",password:String="fixture-password-42",bind:Boolean=false,register:Boolean=false) = runBlocking {
        withTimeout(10000) {
            withContext(Dispatchers.Main) {
                while(vm.syncing.value) delay(20)
                vm.connectAccount(base,username,password,bind,register=register)
                while(vm.syncing.value) delay(20)
            }
        }
    }
    @Test fun invitationBindingAndRenewedLoginPreserveRecordsAndRejectAnotherUser() {
        val record=Record.create(RecordType.BODY).apply {json.put("weight",68)}
        scenario.close()
        app.store.commit(Snapshot(listOf(record),defaultProfile(),emptyList()))
        app.secrets.save("sync","fixture-invitation")
        app.store.set("sync.identity",syncScope(base,"fixture-invitation"))
        scenario=ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity {vm=ViewModelProvider(it)[AppViewModel::class.java]}
        connect(bind=true)
        val first=app.secrets.get("sync")
        assertTrue(first.startsWith("fixture-session-"))
        assertEquals("fixture-user-a",app.store.get("sync.accountId"))
        connect()
        val renewed=app.secrets.get("sync")
        assertNotEquals(first,renewed)
        assertEquals(syncScope(base,renewed),app.store.get("sync.identity"))
        assertEquals(record.id,app.store.load().records.single().id)
        val failure=runCatching {connect("other.user")}.exceptionOrNull()
        assertTrue(failure?.message.orEmpty().contains("其他账号"))
        assertEquals(renewed,app.secrets.get("sync"))
        assertEquals(record.id,app.store.load().records.single().id)
        assertFalse(vm.export().contains("fixture-password-42"))
    }
    @Test fun failedLoginDoesNotSaveCredentialsOrBindLocalRecords() {
        assertNotNull(runCatching {connect(password="wrong fixture password")}.exceptionOrNull())
        assertEquals("",app.secrets.get("sync"))
        assertEquals("",app.store.get("sync.identity"))
        assertEquals("",app.store.get("sync.accountId"))
        assertFalse(vm.syncing.value)
        connect()
        assertEquals("fixture-user-a",app.store.get("sync.accountId"))
    }
    @Test fun selfRegistrationNeedsNoInvitationAndRejectsRegistrationOverBoundData() {
        connect(username="new.user",register=true)
        assertEquals("fixture-new-user",app.store.get("sync.accountId"))
        assertTrue(app.secrets.get("sync").startsWith("fixture-session-"))
        val token=app.secrets.get("sync")
        val requests=app.transport.registrations.get()
        assertTrue(runCatching {connect(username="another.user",register=true)}.exceptionOrNull()?.message.orEmpty().contains("已绑定"))
        assertEquals(requests,app.transport.registrations.get())
        assertEquals(token,app.secrets.get("sync"))
        assertFalse(vm.export().contains("fixture-password-42"))
        connect(username="new.user")
        assertEquals("fixture-new-user",app.store.get("sync.accountId"))
    }
    @Test fun registrationFormChecksConfirmationBeforeSendingAndSignsIn() {
        compose.onNodeWithTag("tab-3").performClick()
        compose.onNodeWithText("你的 LifeRecord").performClick()
        compose.onNodeWithText("注册账号").performClick()
        compose.onNode(hasText("账号") and hasSetTextAction()).performTextReplacement("new.user")
        compose.onNode(hasText("新密码（10–128 个字符）") and hasSetTextAction()).performTextReplacement("fixture-password-42")
        compose.onNode(hasText("确认新密码") and hasSetTextAction()).performTextReplacement("different-password")
        androidx.test.espresso.Espresso.closeSoftKeyboard()
        val requests=app.transport.registrations.get()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("立即同步"))
        compose.onNodeWithText("注册并同步").performClick()
        compose.onNodeWithText("两次输入的密码不一致").assertExists()
        assertEquals(requests,app.transport.registrations.get())
        compose.onNode(hasText("确认新密码") and hasSetTextAction()).performTextReplacement("fixture-password-42")
        androidx.test.espresso.Espresso.closeSoftKeyboard()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("立即同步"))
        compose.onNodeWithText("注册并同步").performClick()
        compose.waitUntil(10000) {app.store.get("sync.accountId")=="fixture-new-user"}
        assertEquals("new.user",app.store.get("sync.username"))
    }
    @Test fun accountFormAndLargeTextKeepInputsAndNavigationReachable() {
        compose.onNodeWithTag("tab-3").performClick()
        compose.onNodeWithText("你的 LifeRecord").performClick()
        compose.onNodeWithText("欢迎回来").assertExists()
        capture("account-login")
        compose.onNodeWithText("注册账号").performClick()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("确认新密码"))
        compose.onNodeWithText("确认新密码").assertIsDisplayed()
        capture("account-setup")
        scenario.onActivity { activity ->
            val density=activity.resources.displayMetrics.density
            activity.setContent {
                CompositionLocalProvider(LocalDensity provides Density(density,1.6f)) { LifeRecordApp(vm) }
            }
        }
        compose.waitForIdle()
        compose.onNodeWithTag("tab-0").performClick()
        compose.onNodeWithContentDescription("今日营养圆环，用餐 0 次").assertExists()
        capture("today-large-text")
        compose.onNodeWithTag("tab-3").performClick()
        compose.onNodeWithText("你的 LifeRecord").performClick()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("登录并同步"))
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("立即同步"))
        compose.onNodeWithText("登录并同步").assertIsDisplayed()
        compose.onNodeWithTag("tab-0").assertIsDisplayed()
        assertTrue(compose.onNodeWithText("登录并同步").fetchSemanticsNode().boundsInRoot.bottom < compose.onNodeWithTag("glass-navigation").fetchSemanticsNode().boundsInRoot.top)
        capture("account-large-text")
    }
    private fun capture(name:String) {
        val instrumentation=androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        if(androidx.test.platform.app.InstrumentationRegistry.getArguments().getString("captureScreenshots")!="true") return
        compose.waitForIdle();android.os.SystemClock.sleep(400)
        val image=instrumentation.uiAutomation.takeScreenshot() ?: error("Screenshot unavailable")
        val folder=java.io.File(app.filesDir,"account-review").apply {mkdirs()}
        java.io.File(folder,"$name.png").outputStream().use {image.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)}
        image.recycle()
    }
}
