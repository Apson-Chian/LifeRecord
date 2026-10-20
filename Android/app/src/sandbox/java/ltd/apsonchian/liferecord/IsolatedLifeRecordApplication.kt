package ltd.apsonchian.liferecord

import android.Manifest
import android.content.pm.PackageManager
import ltd.apsonchian.liferecord.data.Secrets
import ltd.apsonchian.liferecord.data.Store
import ltd.apsonchian.liferecord.service.Network
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

/** Compiled only into the independent sandbox APK, never Debug/Release. */
class IsolatedLifeRecordApplication : LifeRecordApplication() {
    override val store by lazy { Store(this, "instrumented.db") }
    override val secrets by lazy { newSecrets() }
    val transport = IsolatedTransport()
    override val network by lazy {
        Network(OkHttpClient.Builder().addInterceptor(transport).build(), baseURL = { store.get("sync.base", BASE) })
    }
    fun newSecrets() = Secrets(this, "instrumented-secrets", "liferecord.instrumented.secrets")
    override fun onCreate() {
        super.onCreate()
        check(packageName == PACKAGE) { "Refusing to run isolated fixtures in a user package" }
        check(checkSelfPermission(Manifest.permission.INTERNET) == PackageManager.PERMISSION_DENIED)
        store.set("sync.base", BASE)
    }
    companion object {
        const val PACKAGE = "ltd.apsonchian.liferecord.instrumented"
        const val BASE = "https://liferecord-test.invalid/liferecord-api"
    }
}

/** No chain.proceed(), sockets, DNS, upstream credentials or production fallbacks. */
class IsolatedTransport : Interceptor {
    val accepted = AtomicInteger()
    val rejected = AtomicInteger()
    var accountFixtures = false
    val registrations = AtomicInteger()
    private val accountSession = AtomicInteger()
    private val accountUsers = java.util.concurrent.ConcurrentHashMap<String,String>()
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        if(request.url.host != "liferecord-test.invalid" || request.url.scheme != "https") {
            rejected.incrementAndGet()
            throw IOException("Isolated tests prohibit this network destination")
        }
        accepted.incrementAndGet()
        var status = 200
        val body = when(request.url.encodedPath) {
            "/liferecord-api/account/me", "/liferecord-api/account/login", "/liferecord-api/account/register", "/liferecord-api/account/credentials" -> {
                check(accountFixtures) { "Account fixtures must be explicitly enabled" }
                val key = request.header("Authorization").orEmpty().removePrefix("Bearer ")
                val user = if(key == "fixture-invitation") "fixture-user-a" else accountUsers[key]
                val buffer = okio.Buffer(); request.body?.writeTo(buffer)
                val payload = if(buffer.size > 0) JSONObject(buffer.readUtf8()) else JSONObject()
                if(request.url.encodedPath.endsWith("/me")) {
                    if(user == null) {status=401;"""{"error":"请先登录账号"}"""}
                    else JSONObject().put("userId",user).put("username","fixture.user").toString()
                } else {
                    val login = request.url.encodedPath.endsWith("/login")
                    val registering = request.url.encodedPath.endsWith("/register")
                    if(registering) registrations.incrementAndGet()
                    if(((login || registering) && payload.optString("password") != "fixture-password-42") || (!login && !registering && user == null)) {
                        status=401;"""{"error":"账号或密码不正确"}"""
                    } else {
                        val id = if(registering || (login && payload.optString("username") == "new.user")) "fixture-new-user" else if(login && payload.optString("username") == "other.user") "fixture-user-b" else user ?: "fixture-user-a"
                        val token = "fixture-session-${accountSession.incrementAndGet()}"
                        accountUsers[token] = id
                        JSONObject().put("userId",id).put("username",payload.optString("username")).put("token",token).toString()
                    }
                }
            }
            "/liferecord-api/sync" -> {
                val buffer = okio.Buffer(); request.body!!.writeTo(buffer)
                JSONObject(buffer.readUtf8()).put("serverTime", System.currentTimeMillis() / 1000.0).toString()
            }
            else -> throw IOException("No isolated fixture for ${request.url.encodedPath}")
        }
        return Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(status).message("Isolated fixture")
            .body(body.toResponseBody("application/json".toMediaType())).build()
    }
}
