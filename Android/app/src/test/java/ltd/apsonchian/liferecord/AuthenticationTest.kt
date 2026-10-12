package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.service.AIAuthentication
import org.junit.Assert.*
import org.junit.Test
import ltd.apsonchian.liferecord.service.Network
import ltd.apsonchian.liferecord.service.providerConfig
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONObject

class AuthenticationTest {
    @Test fun officialDeepSeekAlwaysReceivesOneBearerHeader() {
        val url="https://api.deepseek.com/chat/completions"
        listOf("sk-local-test-only", " sk-local-test-only\n", "Bearer sk-local-test-only", "Authorization: Bearer sk-local-test-only", "Bearer \"sk-local-test-only\"").forEach { raw ->
            listOf("Bearer","api-key","自定义").forEach { auth ->
                val credential=AIAuthentication.credential(url,auth,"X-API-Key",raw)
                assertEquals("Authorization",credential.header)
                assertEquals("sk-local-test-only",credential.key)
                assertTrue(credential.bearer)
            }
        }
    }
    @Test fun customHostsKeepTheirAuthenticationAndLookalikesAreNotOfficial() {
        assertTrue(AIAuthentication.officialDeepSeek("https://API.DEEPSEEK.COM:443/v1/chat/completions"))
        listOf("https://api.deepseek.com.evil.test/chat/completions","http://api.deepseek.com/chat/completions","https://api.deepseek.com:8443/chat/completions").forEach { assertFalse(AIAuthentication.officialDeepSeek(it)) }
        val credential=AIAuthentication.credential("https://gateway.test/v1/chat/completions","自定义","X-Credential","gateway-key")
        assertFalse(credential.bearer); assertEquals("X-Credential",credential.header)
    }
    @Test fun corruptedAndMaskedKeysAreRejectedBeforeNetworkAccess() {
        listOf("","sk-local\nkey","sk-local\u200bkey","sk-***masked","Bearer Bearer sk-local").forEach { raw ->
            assertThrows(IllegalArgumentException::class.java) { AIAuthentication.normalizedKey(raw,true) }
        }
        assertThrows(IllegalArgumentException::class.java) { AIAuthentication.credential("https://gateway.test","自定义","Invalid Header","key") }
    }
    @Test fun authenticationAndBalanceErrorsHaveDifferentGuidance() {
        assertTrue(AIAuthentication.deepSeekFailure(401)!!.contains("鉴权"))
        assertTrue(AIAuthentication.deepSeekFailure(402)!!.contains("余额"))
        assertNull(AIAuthentication.deepSeekFailure(429))
    }
    @Test fun actualNetworkRequestCorrectsOldAuthAndCleansSavedBearerPrefix() {
        var captured:Request?=null
        val client=OkHttpClient.Builder().addInterceptor { chain ->
            captured=chain.request()
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                .body("""{"choices":[{"message":{"content":"连接成功"}}]}""".toResponseBody("application/json".toMediaType())).build()
        }.build()
        val config=providerConfig("DeepSeek").put("auth","api-key")
        assertEquals("连接成功",Network(client).complete(config,"Bearer sk-local-test-only","测试",listOf(JSONObject().put("role","user").put("content","只回复连接成功"))))
        assertEquals("Bearer sk-local-test-only",captured!!.header("Authorization"))
        assertNull(captured!!.header("api-key"))
        assertEquals("api.deepseek.com",captured!!.url.host)
    }
    @Test fun actualNetwork401ReportsAuthenticationWithoutEchoingSecret() {
        val secret="sk-local-test-only"
        val client=OkHttpClient.Builder().addInterceptor { chain ->
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(401).message("Unauthorized")
                .body("""{"error":{"message":"Invalid key $secret"}}""".toResponseBody("application/json".toMediaType())).build()
        }.build()
        val error=assertThrows(IllegalStateException::class.java) { Network(client).complete(providerConfig("DeepSeek"),secret,"测试",emptyList()) }
        assertTrue(error.message!!.contains("401")); assertTrue(error.message!!.contains("鉴权")); assertFalse(error.message!!.contains(secret))
    }
}
