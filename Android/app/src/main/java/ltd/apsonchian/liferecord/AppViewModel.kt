package ltd.apsonchian.liferecord

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.*
import org.json.*
import java.time.*
import java.util.UUID

data class WeeklyReport(val text: String = "", val generating: Boolean = false, val error: String = "", val generatedAt: Double? = null)
data class Proposal(val actions: List<JSONObject>, val original: Snapshot, val conversation: String, val user: String)
class AppViewModel(application: Application) : AndroidViewModel(application) {
    val app = application as LifeRecordApplication
    private val _snapshot = MutableStateFlow(app.store.load())
    val snapshot = _snapshot.asStateFlow()
    var config = MutableStateFlow(initialAIConfig())
    val apiProfiles = MutableStateFlow(JSONArray(app.store.get("ai.savedProfiles", "[]")).objects())
    private fun initialAIConfig(): JSONObject {
        val old=JSONObject(app.store.get("aiConfig", providerConfig("默认 AI 服务").toString()))
        val migrated=migrateAIConfig(old)
        if(old.optString("provider") == "Dots") {
            val key=app.secrets.get(apiScope(old)).ifBlank { app.secrets.get("ai.Dots") }
            if(key.isNotBlank()) app.secrets.save(apiScope(migrated), key)
            app.store.set("aiConfig", migrated.toString())
        }
        return migrated
    }
    fun saveAPIProfile(name: String, id: String? = null): String {
        require(name.trim().length in 1..60) { "请填写 1–60 字的配置名称" }
        require(id != null || apiProfiles.value.size < 30) { "最多保存 30 个接口配置" }
        val identifier=id ?: UUID.randomUUID().toString()
        val profile=JSONObject().put("id",identifier).put("name",name.trim()).put("config",config.value.copy())
        apiProfiles.value=apiProfiles.value.filterNot { it.optString("id") == identifier } + profile
        app.store.set("ai.savedProfiles",JSONArray(apiProfiles.value).toString())
        return identifier
    }
    fun deleteAPIProfile(id: String) {
        apiProfiles.value=apiProfiles.value.filterNot { it.optString("id") == id }
        app.store.set("ai.savedProfiles",JSONArray(apiProfiles.value).toString())
    }
    val status = MutableStateFlow("记录保存在本机")
    val aiBusy = MutableStateFlow(false)
    val draftPhotos = MutableStateFlow<List<ByteArray>>(emptyList())
    val syncing = MutableStateFlow(false)
    val conversations = MutableStateFlow(JSONArray(app.store.get("conversations", "[]")).objects())
    val selectedConversation = MutableStateFlow(conversations.value.firstOrNull()?.getString("id") ?: "")
    val proposal = MutableStateFlow<Proposal?>(null)
    val todayRequest = MutableStateFlow(0)
    val onboarding = MutableStateFlow(app.store.get("onboarded") != "yes")
    val acknowledgedQuality = MutableStateFlow(JSONArray(app.store.get("recordQuality.acknowledged", "[]")).strings().toSet())
    val weeklyReport = MutableStateFlow(app.store.get("weeklyReport").takeIf { it.isNotBlank() }?.let { raw ->
        runCatching { JSONObject(raw).let { WeeklyReport(it.getString("text"), generatedAt = it.getDouble("generatedAt")) } }.getOrDefault(WeeklyReport())
    } ?: WeeklyReport())
    private var syncJob: Job? = null
    fun confirmQuality(issue: RecordQuality.Issue, confirmed: Boolean) {
        require(RecordQuality.issues(snapshot.value.records).any { it.id == issue.id }) { "记录已更改，请重新核对" }
        val ids = if(confirmed) acknowledgedQuality.value + issue.id else acknowledgedQuality.value - issue.id
        app.store.set("recordQuality.acknowledged", JSONArray(ids.sorted()).toString()); acknowledgedQuality.value = ids
    }
    fun generateWeeklyReport() {
        if(weeklyReport.value.generating) return
        val source = snapshot.value; val at = now(); val start = at.day().minusDays(6)
        val real = source.records.filter { !it.demo && it.date <= at }
        if(real.none { it.type in listOf(RecordType.MEAL, RecordType.BODY, RecordType.WORKOUT) }) {
            weeklyReport.value = weeklyReport.value.copy(error = "先添加真实记录，再生成周报"); return
        }
        val feedback = GoalFeedback.summarize(source.records, source.profile, 7, at, acknowledgedQuality.value)
        val weights = BodyTrend.records(real, "weight", at).filter { it.day >= start }
        val fat = BodyTrend.records(real, "bodyFat", at).filter { it.day >= start }
        val nutrition = real.filter { it.type == RecordType.MEAL && it.date.day() >= start && RecordQuality.validNutrition(it) }.groupBy { it.date.day() }.toSortedMap().map { (day, entries) ->
            "$day: ${format(Insights.total(entries, "calories"))} kcal / P${format(Insights.total(entries, "protein"))} g"
        }
        val workouts = real.filter { it.type == RecordType.WORKOUT && it.date.day() >= start }
        val issues = RecordQuality.issues(source.records, at).filter { it.date.day() >= start && it.date <= at && it.id !in acknowledgedQuality.value }
        val context = """最近七天（含今天），$start 至 ${at.day()}。目标：${source.profile}。
本机目标反馈：${feedback.context}。待核对：${issues.joinToString("、") { it.title }}。
体重：${weights.joinToString { "${it.day}: 中位数 ${it.value} kg，趋势 ${it.trend} kg，${it.count} 次" }}。
体脂：${fat.joinToString { "${it.day}: 中位数 ${it.value}%，趋势 ${it.trend}%" }}。
每日营养：${nutrition.joinToString("；")}。
训练起止、部位、备注和逐组数据：${JSONArray(workouts.map { it.json.copy().apply { remove("localPhotoFiles"); remove("uploadedPhotoFiles") } })}。
每日中位数后按实际间隔指数平滑；无记录不代表零，今日记录尚未结束。"""
        val c = config.value.copy(); val key = aiKey(c)
        weeklyReport.value = weeklyReport.value.copy(generating = true, error = "")
        viewModelScope.launch {
            try {
                val text = withContext(Dispatchers.IO) { app.network.complete(c, key,
                    "依据用户设定目标与本机统计，用中文按“目标距离、执行情况、记录不足、下周行动”复盘。引用记录天数和达标天数，缺失日期不按零摄入计算，今日尚未结束。先提醒待核对数据；体重进度不等同于肌肉或脂肪变化，不预测到达日期，不自动调整目标，不输出写入操作。最后给 2–3 条具体行动，不做医疗诊断，不鼓励极端热量缺口。",
                    listOf(JSONObject().put("role", "user").put("content", context))) }
                app.store.set("weeklyReport", JSONObject().put("text", text).put("generatedAt", at).toString())
                weeklyReport.value = WeeklyReport(text, generatedAt = at)
            } catch(e: CancellationException) { weeklyReport.value = weeklyReport.value.copy(generating = false); throw e }
            catch(e: Exception) { weeklyReport.value = weeklyReport.value.copy(generating = false, error = e.message.orEmpty()) }
        }
    }
    private fun persist(s: Snapshot) { app.store.commit(s); _snapshot.value = s; ReminderWorker.schedule(app) }
    fun save(r: Record, photos: List<ByteArray> = emptyList()) {
        Validation.record(r)
        val local = r.json.optJSONArray("localPhotoFiles")?.strings().orEmpty()
        val uploaded = r.json.optJSONArray("uploadedPhotoFiles")?.strings().orEmpty()
        require((r.json.optJSONArray("photoIDs")?.length() ?: 0) + (local - uploaded.toSet()).size + photos.size <= 12) { "每条记录最多保存 12 张照片" }
        val latest = snapshot.value.records.find { it.id == r.id && it.type == r.type }
        require(latest == null || latest.updated == r.updated) { "记录已被同步更新，请重新打开编辑" }
        val copy = r.copy(); copy.json.put("updatedAt", now())
        if(photos.isNotEmpty()) copy.json.put("localPhotoFiles", JSONArray(copy.json.optJSONArray("localPhotoFiles")?.strings().orEmpty() + photos.map { app.photos.save(it) }))
        persist(snapshot.value.copy(records = snapshot.value.records.filterNot { it.id == r.id && it.type == r.type } + copy))
        sync()
    }
    fun delete(r: Record) {
        val tomb = JSONObject().put("id", r.id).put("recordType", r.type.wire).put("deletedAt", now())
        val syncable = r.type in listOf(RecordType.MEAL, RecordType.BODY, RecordType.WORKOUT) && !r.demo
        persist(snapshot.value.copy(records = snapshot.value.records.filterNot { it.id == r.id && it.type == r.type }, deletions = snapshot.value.deletions + if(syncable) listOf(tomb) else emptyList()))
        sync()
    }
    fun saveProfile(p: JSONObject) { require(p.optDouble("updatedAt") == snapshot.value.profile.optDouble("updatedAt")) { "档案已被同步更新，请重新打开编辑" }; Validation.profile(p); persist(snapshot.value.copy(profile = p.copy().put("updatedAt", now()))); sync() }
    fun saveConfig(c: JSONObject, apiKey: String?) {
        if(c.optString("provider") != "默认 AI 服务") validateHTTPS(c.optString("endpoint"))
        require(c.optString("provider") == "默认 AI 服务" || c.optString("model").isNotBlank()) { "请填写模型名" }
        require(c.optInt("maxPhotos") in 1..12 && c.optInt("maxTokens") in 256..65536 && c.optDouble("temperature") in 0.0..2.0) { "请核对生成参数" }
        if(AIAuthentication.officialDeepSeek(c.getString("endpoint"))) c.put("auth", "Bearer")
        require(c.optString("tokenParameter", "max_tokens") in listOf("max_tokens", "max_completion_tokens")) { "输出参数无效" }
        val extra = JSONObject(c.optString("extraBody", "{}").ifBlank { "{}" })
        require(extra.keys().asSequence().none { it in listOf("messages", "model", "stream", "temperature", "max_tokens", "max_completion_tokens", "response_format") }) { "扩展参数不能覆盖模型、消息和生成设置" }
        if(apiKey != null) app.secrets.save(apiScope(c), AIAuthentication.normalizedKey(apiKey, c.optString("auth") == "Bearer"))
        app.store.set("ai.profile.${c.getString("provider")}", c.toString()); app.store.set("aiConfig", c.toString()); config.value = c.copy()
    }
    private fun aiKey(c: JSONObject): String {
        if(c.optString("provider") == "默认 AI 服务") {
            val base=app.store.get("sync.base",Network.BASE);val key=app.secrets.get("sync")
            require(key.isNotBlank()) { "请先连接你的独立账号，再使用默认 AI 服务" }
            require(app.store.get("sync.identity")==syncScope(base,key)) { "账号与本机数据不匹配，请先在同步设置中连接" }
            return key
        }
        val scoped = app.secrets.get(apiScope(c))
        if(scoped.isNotBlank()) return scoped
        // Only a preset's exact URL may read its old provider credential.
        return if(c.optString("endpoint") == providerConfig(c.optString("provider")).optString("endpoint") && c.optString("provider") != "自定义") app.secrets.get("ai.${c.optString("provider")}") else ""
    }
    val dataGeneration = MutableStateFlow(0)
    val appearance = MutableStateFlow(app.store.get("appearance", "system"))
    val accent = MutableStateFlow(app.store.get("accent", "purple"))
    fun personalize(mode: String, color: String) {
        app.store.set("appearance", mode); app.store.set("accent", color)
        appearance.value=mode; accent.value=color
    }
    fun saveSyncKey(key: String, base: String = app.store.get("sync.base", Network.BASE)) {
        require(!syncing.value) { "请等待当前同步结束" }
        validateHTTPS(base)
        val token = key.trim()
        if(token.isNotBlank()) {
            val scope = syncScope(base,token)
            val previous=app.store.get("sync.identity")
            require(previous.isBlank() || previous == scope) { "此设备已有其他账号的数据；请先导出并清除本机数据，再连接新账号" }
            app.store.set("sync.identity",scope)
        }
        app.store.set("sync.base",base.trimEnd('/'))
        app.secrets.save("sync", token); status.value = if(key.isBlank()) "同步已关闭" else "同步密钥已保存"; sync()
    }
    fun resetLocalData() {
        require(!syncing.value && !aiBusy.value && !weeklyReport.value.generating) { "请等待同步和 AI 任务结束" }
        app.secrets.clear(); app.store.clearAll()
        apiProfiles.value=emptyList()
        config.value=providerConfig("默认 AI 服务"); appearance.value="system";accent.value="purple"
        draftPhotos.value=emptyList();dataGeneration.value++
        persist(Snapshot(emptyList(), defaultProfile(), emptyList()))
        saveChats(emptyList()); selectedConversation.value=""; proposal.value=null
        weeklyReport.value=WeeklyReport(); app.store.set("weeklyReport", "")
        acknowledgedQuality.value=emptySet(); app.store.set("recordQuality.acknowledged", "[]")
        app.store.set("sync.identity", ""); app.photos.clearAll(); status.value="本机数据已清除，云端数据保留"
    }
    fun foreground(active: Boolean) {
        syncJob?.cancel(); syncJob = null
        if(active) syncJob = viewModelScope.launch { while(isActive) { sync(); delay(15000) } }
    }
    fun sync() {
        if(syncing.value) return
        viewModelScope.launch {
            syncing.value = true
            try {
                val key = app.secrets.get("sync"); if(key.isBlank()) return@launch
                val scope = syncScope(app.store.get("sync.base", Network.BASE),key)
                val previous=app.store.get("sync.identity")
                require(previous.isBlank() || previous == scope) { "账号与本机数据不匹配，请清除本机数据后再连接" }
                app.store.set("sync.identity",scope)
                status.value = "正在同步…"
                var photoError = ""
                // Finish queued photo uploads. Preserve local copies for offline viewing.
                snapshot.value.records.filter { it.type == RecordType.MEAL && !it.demo }.forEach { r ->
                    val local = r.json.optJSONArray("localPhotoFiles")?.strings().orEmpty()
                    val uploaded = r.json.optJSONArray("uploadedPhotoFiles")?.strings().orEmpty()
                    for(name in local - uploaded.toSet()) {
                        val id = try { withContext(Dispatchers.IO) { app.network.upload(app.photos.local(name), r.id, key) } }
                        catch(e: Exception) { photoError = e.message.orEmpty(); break }
                        if(app.secrets.get("sync") != key) return@launch
                        val current = snapshot.value.records.find { it.id == r.id && it.type == r.type } ?: break
                        val changed = current.copy()
                        changed.json.put("photoIDs", JSONArray(changed.json.optJSONArray("photoIDs")?.strings().orEmpty() + id))
                        changed.json.put("uploadedPhotoFiles", JSONArray(changed.json.optJSONArray("uploadedPhotoFiles")?.strings().orEmpty() + name))
                        changed.json.put("updatedAt", now()); persist(snapshot.value.copy(records = snapshot.value.records.map { if(it.id == r.id && it.type == r.type) changed else it }))
                    }
                }
                val outbound = snapshot.value
                val response = withContext(Dispatchers.IO) { app.network.sync(outbound, key) }
                // Merge against current state after network roundtrip, never stale outbound state.
                if(app.secrets.get("sync") != key) return@launch
                persist(Merge.apply(snapshot.value, response)); status.value = if(photoError.isBlank()) "所有设备已同步 · ${LocalTime.now().withSecond(0).withNano(0)}" else "记录已同步，照片等待重试：$photoError"
            } catch(e: CancellationException) { throw e } catch(e: Exception) { status.value = "同步失败：${e.message ?: "网络不可用"}" } finally { syncing.value = false }
        }
    }
    fun startWorkout() {
        require(snapshot.value.records.none { it.type == RecordType.WORKOUT && it.json.isNull("endDate") }) { "已有训练正在进行，请先结束" }
        save(Record.create(RecordType.WORKOUT))
    }
    fun endWorkout(r: Record) { save(r.copy().apply { json.put("endDate", now()) }) }
    suspend fun readPhotos(uris: List<Uri>) = withContext(Dispatchers.IO) { uris.map { app.photos.read(it) } }
    suspend fun photo(r: Record, id: String, local: Boolean) = withContext(Dispatchers.IO) { if(local) app.photos.local(id) else app.photos.remote(id, app.secrets.get("sync"), app.network) }
    suspend fun nutrition(input: String, images: List<ByteArray>, old: Record?): JSONObject = withContext(Dispatchers.IO) {
        val c = config.value.copy()
        val result = app.network.complete(c, aiKey(c),
            "识别或按要求修改整餐营养。只输出 JSON {name,calories,protein,carbs,fat,fiber,note}，单位 kcal/g，未知份量在 note 中说明。不得凭空给精确数值。", listOf(JSONObject().put("role", "user").put("content", input + (old?.let { "\n当前餐食：${it.json.copy().apply { remove("localPhotoFiles"); remove("uploadedPhotoFiles") }}" } ?: ""))), images, true)
        parseObject(result)
    }
    suspend fun testConnection(): String = withContext(Dispatchers.IO) {
        val c = config.value
        app.network.complete(c, aiKey(c), "只回复：连接成功", listOf(JSONObject().put("role", "user").put("content", "测试连接")))
    }
    private fun saveChats(values: List<JSONObject>) { app.store.set("conversations", JSONArray(values).toString()); conversations.value = values }
    fun newConversation(): String {
        val id = UUID.randomUUID().toString()
        saveChats(listOf(JSONObject().put("id", id).put("title", "新的对话").put("messages", JSONArray())) + conversations.value)
        selectedConversation.value = id; return id
    }
    fun deleteConversation(id: String) {
        require(!aiBusy.value) { "回答仍在生成，请稍后删除" }
        val photos = conversations.value.firstOrNull { it.optString("id") == id }?.optJSONArray("messages")?.objects()?.flatMap { it.optJSONArray("localPhotoFiles")?.strings().orEmpty() }.orEmpty()
        saveChats(conversations.value.filterNot { it.getString("id") == id })
        photos.forEach { runCatching { app.photos.deleteChat(it) } }
        selectedConversation.value = conversations.value.firstOrNull()?.getString("id") ?: ""; if(proposal.value?.conversation == id) proposal.value = null }
    private fun append(id: String, role: String, content: String, photos: List<String> = emptyList()) {
        saveChats(conversations.value.map { chat -> if(chat.getString("id") == id) chat.copy().apply {
            put("messages", JSONArray(getJSONArray("messages").objects() + JSONObject().put("role", role).put("content", content).put("localPhotoFiles", JSONArray(photos))))
            if(role == "user" && getString("title") == "新的对话") put("title", content.take(20))
        } else chat })
    }
    fun send(text: String, images: List<ByteArray> = emptyList()) {
        if(aiBusy.value || (text.isBlank() && images.isEmpty())) return
        val id = selectedConversation.value.ifBlank { newConversation() }; val user = text.ifBlank { "请分析图片" }
        val localPhotos = mutableListOf<String>()
        try { images.forEach { localPhotos += app.photos.saveChat(it) }; append(id, "user", user, localPhotos) }
        catch(e: Exception) { localPhotos.forEach { app.photos.deleteChat(it) }; throw e }
        aiBusy.value = true; proposal.value = null
        viewModelScope.launch {
            try {
                val original = snapshot.value
                val context = Merge.wire(original).put("favorites", JSONArray(original.records.filter { it.type == RecordType.FAVORITE }.map { it.json.copy().apply { remove("localPhotoFiles");remove("uploadedPhotoFiles") } })).put("exerciseTemplates", JSONArray(original.records.filter { it.type == RecordType.EXERCISE }.map { it.json }))
                val c = config.value.copy()
                val history = conversations.value.first { it.getString("id") == id }.getJSONArray("messages").objects()
                val reply = withContext(Dispatchers.IO) { parseObject(app.network.complete(c, aiKey(c), AgentActions.PROMPT + "\n本地时间：${OffsetDateTime.now()}\n当前数据：$context", history, images, true)) }
                append(id, "assistant", reply.getString("answer"))
                val actions = reply.optJSONArray("actions")?.objects().orEmpty()
                if(actions.isNotEmpty()) {
                    if(c.optBoolean("canWrite")) { AgentActions.apply(original, actions, user, id); proposal.value = Proposal(actions, original, id, user) }
                    else append(id, "assistant", "未写入记录。可在设置中开启 AI 写入，之后会提供复核草稿。")
                }
            } catch(e: Exception) { append(id, "assistant", "请求失败：${e.message ?: "请检查接口设置"}") } finally { aiBusy.value = false }
        }
    }
    fun applyProposal() {
        val p = proposal.value ?: return
        require(fingerprint(snapshot.value) == fingerprint(p.original)) { "生成草稿后记录发生变化，请重新发送请求" }
        persist(AgentActions.apply(snapshot.value, p.actions, p.user, p.conversation)); proposal.value = null
        append(p.conversation, "assistant", "已保存 ${p.actions.size} 项操作，可在记录页面核对。"); sync()
    }
    private fun fingerprint(s: Snapshot) = s.records.sortedBy { it.id }.joinToString { "${it.type}:${it.id}:${it.updated}" } + s.profile.optDouble("updatedAt") + JSONArray(s.deletions)
    fun completeOnboarding() { app.store.set("onboarded", "yes"); onboarding.value = false }
    fun seedDemo() {
        val records = (0L..13L).flatMap { offset ->
            val day = LocalDate.now().minusDays(offset)
            listOf(Record.create(RecordType.MEAL, day.epochAt(LocalTime.NOON)).apply { json.put("name", "鸡胸肉杂粮饭（示例）"); json.put("calories", 620); json.put("protein", 42); json.put("carbs", 72); json.put("fat", 17); json.put("isDemo", true) },
                Record.create(RecordType.BODY, day.epochAt(LocalTime.of(8,0))).apply { json.put("weight", 65.0+offset*0.08); json.put("isDemo", true) })
        }; persist(snapshot.value.copy(records = snapshot.value.records.filterNot { it.demo } + records))
    }
    fun clearDemo() { persist(snapshot.value.copy(records = snapshot.value.records.filterNot { it.demo })) }
    fun export(): String = Merge.wire(snapshot.value).put("favorites", JSONArray(snapshot.value.records.filter { it.type == RecordType.FAVORITE }.map { it.json.copy().apply { remove("localPhotoFiles") } })).put("exerciseTemplates", JSONArray(snapshot.value.records.filter { it.type == RecordType.EXERCISE }.map { it.json })).toString(2)
}
