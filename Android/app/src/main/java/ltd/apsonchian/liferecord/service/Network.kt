package ltd.apsonchian.liferecord.service

import ltd.apsonchian.liferecord.data.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import android.util.Base64

class Network(private val client: OkHttpClient = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).callTimeout(100, TimeUnit.SECONDS).build(), private val baseURL: () -> String = { BASE }) {
    private fun execute(url: String, secret: String, body: JSONObject?, header: String = "Authorization", bearer: Boolean = true, officialDeepSeek: Boolean = false, onCall: ((Call) -> Unit)? = null): ByteArray {
        require(url.startsWith("https://")) { "接口地址需要使用 HTTPS" }
        require(secret.isNotBlank()) { "请先配置密钥" }
        require(secret.all { it.code in 33..126 }) { "密钥不能包含空格、换行或中文，请重新粘贴" }
        val request = Request.Builder().url(url).header(header, if(bearer) "Bearer $secret" else secret).apply {
            if(body != null) post(body.toString().toRequestBody("application/json".toMediaType()))
        }.build()
        val call=client.newBuilder().followRedirects(false).followSslRedirects(false).callTimeout(100, TimeUnit.SECONDS).build().newCall(request)
        onCall?.invoke(call)
        return call.execute().use { response ->
            val bytes = response.body?.bytes() ?: error("服务端返回空数据")
            if(!response.isSuccessful) {
                if(officialDeepSeek) AIAuthentication.deepSeekFailure(response.code)?.let { error(it) }
                // Error bodies can contain request echoes. Never display credentials.
                val summary = runCatching { JSONObject(bytes.toString(Charsets.UTF_8)).let { it.optJSONObject("error")?.optString("message") ?: it.optString("error", it.optString("message", "请求被拒绝")) } }.getOrDefault("请求被拒绝")
                error("HTTP ${response.code}：${summary.replace(secret, "[密钥已隐藏]").take(240)}")
            }; bytes
        }
    }
    fun sync(snapshot: Snapshot, key: String): JSONObject = JSONObject(execute("${baseURL().trimEnd('/')}/sync", key, Merge.wire(snapshot)).toString(Charsets.UTF_8))
    fun upload(bytes: ByteArray, mealId: String, key: String): String = JSONObject(execute("${baseURL().trimEnd('/')}/images", key, JSONObject().put("mealId", mealId).put("base64", Base64.encodeToString(bytes, Base64.NO_WRAP))).toString(Charsets.UTF_8)).getString("id")
    fun photo(id: String, key: String): ByteArray {
        require(id.matches(Regex("[0-9a-f]{32}"))) { "图片编号无效" }
        return execute("${baseURL().trimEnd('/')}/images/$id", key, null)
    }
    fun complete(config: JSONObject, key: String, system: String, messages: List<JSONObject>, images: List<ByteArray> = emptyList(), json: Boolean = false, onCall: ((Call) -> Unit)? = null): String {
        if(config.optString("provider") == "默认 AI 服务") return defaultComplete(config,key,system,messages,images,onCall)
        require(config.optString("model").isNotBlank()) { "请填写模型名" }
        require(images.isEmpty() || config.optBoolean("vision")) { "当前接口未启用图片能力" }
        require(images.size <= config.optInt("maxPhotos", 6)) { "图片超出设置中的数量限制" }
        val list = JSONArray().put(JSONObject().put("role", "system").put("content", system + "\n" + config.optString("instructions")))
        messages.takeLast(14).forEachIndexed { index, original ->
            val m = JSONObject().put("role", original.getString("role")).put("content", original.getString("content"))
            if(index == messages.takeLast(14).lastIndex && images.isNotEmpty()) {
                val content = JSONArray().put(JSONObject().put("type", "text").put("text", m.getString("content")))
                images.forEach { bytes -> content.put(JSONObject().put("type", "image_url").put("image_url", JSONObject().put("url", "data:image/jpeg;base64," + Base64.encodeToString(bytes, Base64.NO_WRAP)).apply { if(config.optString("imageDetail").isNotBlank()) put("detail", config.optString("imageDetail")) })) }
                m.put("content", content)
            }; list.put(m)
        }
        val body = JSONObject().put("model", config.getString("model")).put("messages", list).put("stream", false)
            .put(config.optString("tokenParameter", "max_tokens"), config.optInt("maxTokens", 4096).coerceIn(256, 65536)).put("temperature", config.optDouble("temperature", 0.2))
        if(!config.optBoolean("sendTemperature", true)) body.remove("temperature")
        val extras = JSONObject(config.optString("extraBody", "{}").ifBlank { "{}" })
        require(extras.keys().asSequence().none { it in listOf("model", "messages", "stream", "max_tokens", "max_completion_tokens", "temperature", "response_format") }) { "扩展参数不能覆盖模型、消息和生成设置" }
        extras.keys().forEach { body.put(it, extras.get(it)) }
        when(config.optString("provider")) {
            "DeepSeek", "智谱 GLM" -> body.put("thinking", JSONObject().put("type", "disabled"))
        }
        if(json && config.optBoolean("jsonMode", true) && images.isEmpty()) body.put("response_format", JSONObject().put("type", "json_object"))
        val endpoint = config.getString("endpoint").trim()
        val credential = AIAuthentication.credential(endpoint, config.optString("auth", "Bearer"), config.optString("header", "Authorization"), key)
        val bytes = execute(endpoint, credential.key, body, credential.header, credential.bearer, AIAuthentication.officialDeepSeek(endpoint), onCall)
        val result = JSONObject(bytes.toString(Charsets.UTF_8)); return result.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")?.optString("content")?.takeIf { it.isNotBlank() } ?: error("没有收到模型最终回复，请检查模型与生成参数")
    }
    private fun defaultComplete(config:JSONObject,key:String,system:String,messages:List<JSONObject>,images:List<ByteArray>,onCall:((Call)->Unit)?):String {
        require(images.size <= config.optInt("maxPhotos",6)) { "图片超出设置中的数量限制" }
        require(images.isEmpty() || config.optBoolean("vision",true)) { "当前设置未启用图片能力" }
        val list=JSONArray().put(JSONObject().put("role","system").put("content",system+"\n"+config.optString("instructions")))
        messages.takeLast(14).forEachIndexed { index,original ->
            val m=JSONObject().put("role",original.getString("role")).put("content",original.getString("content"))
            if(index==messages.takeLast(14).lastIndex && images.isNotEmpty()) {
                val parts=JSONArray().put(JSONObject().put("type","text").put("text",m.getString("content")))
                images.forEach { bytes -> parts.put(JSONObject().put("type","image_url").put("image_url",JSONObject().put("url","data:image/jpeg;base64,"+Base64.encodeToString(bytes,Base64.NO_WRAP)))) }
                m.put("content",parts)
            }
            list.put(m)
        }
        val body=JSONObject().put("messages",list).put("maxTokens",config.optInt("maxTokens",4096))
        val bytes=execute("${baseURL().trimEnd('/')}/ai/chat",key,body,onCall=onCall)
        return JSONObject(bytes.toString(Charsets.UTF_8)).getJSONArray("choices").getJSONObject(0).getJSONObject("message").getString("content")
    }
    companion object { const val BASE = "https://apsonchian.ltd/liferecord-api" }
}
val providers = listOf("默认 AI 服务", "DeepSeek", "智谱 GLM", "自定义")
fun providerConfig(provider: String) = JSONObject().apply {
    put("provider", provider); put("auth", if(provider == "Dots") "api-key" else "Bearer"); put("header", "Authorization")
    put("endpoint", when(provider) { "DeepSeek" -> "https://api.deepseek.com/chat/completions"; "智谱 GLM" -> "https://open.bigmodel.cn/api/paas/v4/chat/completions"; else -> "https://example.com/v1/chat/completions" })
    put("model", when(provider) { "DeepSeek" -> "deepseek-flash"; "智谱 GLM" -> "glm-4.6v-flash"; else -> "" })
    put("vision", true); put("maxPhotos", 6); put("maxTokens", 4096); put("temperature", 0.2); put("instructions", ""); put("canWrite", false); put("sendTemperature", true); put("jsonMode", true); put("tokenParameter", "max_tokens"); put("extraBody", "{}")
}
fun migrateAIConfig(config: JSONObject): JSONObject = config.copy().apply {
    if(optString("provider") == "Dots") {
        put("provider", "自定义");put("jsonMode", false);put("imageDetail", "medium")
        val extra = JSONObject(optString("extraBody", "{}").ifBlank { "{}" })
        if(!extra.has("chat_template_kwargs")) extra.put("chat_template_kwargs", JSONObject().put("enable_thinking", false))
        put("extraBody", extra.toString())
    }
}
fun parseObject(text: String): JSONObject {
    val trimmed = text.trim().removePrefix("```json").removePrefix("```").removeSuffix("```").trim()
    return JSONObject(trimmed)
}
object AgentActions {
    /** Validate a whole draft against a snapshot before committing; omitted fields stay unchanged. */
    fun apply(snapshot: Snapshot, actions: List<JSONObject>, userText: String, conversationId: String): Snapshot {
        require(actions.size <= 30) { "单次最多 30 项操作" }
        var result = Snapshot(snapshot.records.map { it.copy() }, snapshot.profile.copy(), snapshot.deletions.map { it.copy() })
        actions.forEach { a ->
            val operation = a.getString("type")
            if(operation == "update_goals") {
                val p = result.profile.copy()
                listOf("displayName", "fitnessGoal", "height", "baselineWeight", "targetWeight", "weeklyWeightTarget", "calorieGoal", "proteinGoal", "carbsGoal", "fatGoal").forEach { if(a.has(it)) p.put(it, a.get(it)) }
                Validation.profile(p); p.put("updatedAt", now()); result = result.copy(profile = p)
            } else {
                val type = when(operation.substringAfter('_')) { "meal" -> RecordType.MEAL; "weight" -> RecordType.BODY; "workout" -> RecordType.WORKOUT; "exercise_template" -> RecordType.EXERCISE; else -> error("不支持的操作：$operation") }
                val mode = operation.substringBefore('_'); require(mode in listOf("add", "update", "delete"))
                val old = if(mode != "add") result.records.singleOrNull { it.type == type && it.id.equals(a.optString("recordID"), true) } ?: error("原记录不存在，请重新生成草稿") else null
                if(mode == "delete") {
                    val tomb = JSONObject().put("id", old!!.id).put("recordType", type.wire).put("deletedAt", now())
                    result = result.copy(records = result.records.filterNot { it.id == old.id && it.type == type }, deletions = result.deletions + if(type == RecordType.EXERCISE) emptyList() else listOf(tomb))
                } else {
                    val r = old?.copy() ?: Record.create(type)
                    if(mode == "add") {
                        if(type == RecordType.WORKOUT) require(a.has("endDate") && !a.isNull("endDate")) { "新增训练需要起止时间" }
                        if(type == RecordType.MEAL) require(a.optString("name").isNotBlank() && a.has("calories") && !a.isNull("calories")) { "新增餐食需要名称和热量" }
                        if(type == RecordType.BODY) require(a.has("weight") && !a.isNull("weight")) { "新增身体测量需要体重" }
                        if(type == RecordType.MEAL) { r.json.put("inputText", userText); r.json.put("sourceConversationID", conversationId); r.json.put("source", "AI 估算") }
                    }
                    val allowed = when(type) {
                        RecordType.MEAL -> listOf("name", "calories", "protein", "carbs", "fat", "fiber", "note", "source")
                        RecordType.BODY -> listOf("weight", "bodyFat", "waist", "note")
                        RecordType.WORKOUT -> listOf("bodyParts", "exercises", "note")
                        else -> listOf("name", "bodyPart")
                    }
                    allowed.forEach { if(a.has(it)) r.json.put(it, a.get(it)) }
                    if(a.has("mealKind")) r.json.put("kind", a.getString("mealKind"))
                    listOf("date", "endDate").forEach { if(a.has(it)) r.json.put(it, if(a.isNull(it)) JSONObject.NULL else java.time.OffsetDateTime.parse(a.getString(it)).toInstant().toEpochMilli() / 1000.0) }
                    if(a.optBoolean("clearBodyFat")) r.json.put("bodyFat", JSONObject.NULL)
                    if(a.optBoolean("clearWaist")) r.json.put("waist", JSONObject.NULL)
                    if(a.optBoolean("clearBodyPart")) r.json.put("bodyPart", JSONObject.NULL)
                    r.json.put("updatedAt", now()); Validation.record(r)
                    result = result.copy(records = result.records.filterNot { it.type == type && it.id == r.id } + r)
                }
            }
        }; return result
    }
    const val PROMPT = """你是生活记录健身教练，结合本机记录用中文回答。所有记录时间使用本地时区 ISO8601。输出 JSON {"answer":"回答","actions":[]}。
只有用户明确要求新增、修改、删除或修改目标时生成 actions。用户描述已经吃下的食物并要求添加到餐食时，结合上下文必须返回 add_meal；上一轮描述食物、本轮要求记录也属于记录请求。营养值未知时可按份量估算，note 说明依据和不确定性；不知道吃了什么时先询问。明显属于实际摄入的餐食/饮料照片且没有要求“只分析/不要记录”时返回 add_meal；配料表、包装、菜单不代表已摄入。训练计划不当作已完成训练。
操作 type：add_meal/update_meal/delete_meal、add_weight/update_weight/delete_weight、add_workout/update_workout/delete_workout、add_exercise_template/update_exercise_template/delete_exercise_template、update_goals。
修改/删除必须使用上下文中准确 recordID，歧义先询问；修改只输出改变的字段，不能清空未提及字段。date/endDate 仅在修改时间时输出。新增记录给出 date，用户没说明时间时使用当前本地时间；昨天或餐次要保留对应日期。新增训练需要明确起止时间，缺失先询问。
餐食字段 mealKind(早餐/午餐/晚餐/加餐)、name、calories、protein、carbs、fat、fiber、note。身体字段 weight、bodyFat、waist、note，清空可用 clearBodyFat/clearWaist。
训练字段 bodyParts 数组、exercises:[{name,bodyPart,sets:[{reps,weight,durationSeconds}]}]、note。未知逐组数值为 null，不编造。动作库 name、bodyPart，清空用 clearBodyPart。
目标字段 displayName、fitnessGoal(增肌/减脂/维持)、height、baselineWeight、targetWeight、weeklyWeightTarget、calorieGoal、proteinGoal、carbsGoal、fatGoal。
优先使用常用餐食的固定营养。咨询、计划吃、否认吃过或要求不要记录时不新增。不得声称已执行或已保存，App 会在验证并实际保存后显示回执。"""
}

fun apiScope(config: JSONObject): String = "ai." + config.optString("provider") + "." + java.security.MessageDigest.getInstance("SHA-256").digest(config.optString("endpoint").trim().toByteArray()).joinToString("") { "%02x".format(it) }
fun syncScope(base: String, key: String): String = java.security.MessageDigest.getInstance("SHA-256").digest((base.trimEnd('/') + "\n" + key).toByteArray()).joinToString("") { "%02x".format(it) }
fun validateHTTPS(endpoint: String) {
    val url = java.net.URI(endpoint.trim())
    require(url.scheme == "https" && !url.host.isNullOrBlank() && url.userInfo == null && url.fragment == null) { "请填写不含用户名和片段的完整 HTTPS 地址" }
}
