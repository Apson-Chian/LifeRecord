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

data class Proposal(val actions: List<JSONObject>, val original: Snapshot, val conversation: String, val user: String)
class AppViewModel(application: Application) : AndroidViewModel(application) {
    val app = application as LifeRecordApplication
    private val _snapshot = MutableStateFlow(app.store.load())
    val snapshot = _snapshot.asStateFlow()
    var config = MutableStateFlow(JSONObject(app.store.get("aiConfig", providerConfig("DeepSeek").toString())))
    val status = MutableStateFlow("记录保存在本机")
    val aiBusy = MutableStateFlow(false)
    val syncing = MutableStateFlow(false)
    val conversations = MutableStateFlow(JSONArray(app.store.get("conversations", "[]")).objects())
    val selectedConversation = MutableStateFlow(conversations.value.firstOrNull()?.getString("id") ?: "")
    val proposal = MutableStateFlow<Proposal?>(null)
    val todayRequest = MutableStateFlow(0)
    val onboarding = MutableStateFlow(app.store.get("onboarded") != "yes")
    private var syncJob: Job? = null
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
        require(c.optString("endpoint").startsWith("https://")) { "请使用 HTTPS 接口" }
        require(c.optString("model").isNotBlank()) { "请填写模型名" }
        require(c.optInt("maxPhotos") in 1..12 && c.optInt("maxTokens") in 256..4096 && c.optDouble("temperature") in 0.0..2.0) { "请核对生成参数" }
        if(AIAuthentication.officialDeepSeek(c.getString("endpoint"))) c.put("auth", "Bearer")
        if(apiKey != null) app.secrets.save("ai.${c.getString("provider")}", AIAuthentication.normalizedKey(apiKey, c.optString("auth") == "Bearer"))
        app.store.set("aiConfig", c.toString()); config.value = c.copy()
    }
    fun saveSyncKey(key: String) { app.secrets.save("sync", key.trim()); status.value = if(key.isBlank()) "同步已关闭" else "同步密钥已保存"; sync() }
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
        val result = app.network.complete(c, app.secrets.get("ai.${c.getString("provider")}"),
            "识别或按要求修改整餐营养。只输出 JSON {name,calories,protein,carbs,fat,fiber,note}，单位 kcal/g，未知份量在 note 中说明。不得凭空给精确数值。", listOf(JSONObject().put("role", "user").put("content", input + (old?.let { "\n当前餐食：${it.json}" } ?: ""))), images, true)
        parseObject(result)
    }
    suspend fun testConnection(): String = withContext(Dispatchers.IO) {
        val c = config.value
        app.network.complete(c, app.secrets.get("ai.${c.getString("provider")}"), "只回复：连接成功", listOf(JSONObject().put("role", "user").put("content", "测试连接")))
    }
    private fun saveChats(values: List<JSONObject>) { app.store.set("conversations", JSONArray(values).toString()); conversations.value = values }
    fun newConversation(): String {
        val id = UUID.randomUUID().toString()
        saveChats(listOf(JSONObject().put("id", id).put("title", "新的对话").put("messages", JSONArray())) + conversations.value)
        selectedConversation.value = id; return id
    }
    fun deleteConversation(id: String) { saveChats(conversations.value.filterNot { it.getString("id") == id }); selectedConversation.value = conversations.value.firstOrNull()?.getString("id") ?: ""; if(proposal.value?.conversation == id) proposal.value = null }
    private fun append(id: String, role: String, content: String) {
        saveChats(conversations.value.map { chat -> if(chat.getString("id") == id) chat.copy().apply {
            put("messages", JSONArray(getJSONArray("messages").objects() + JSONObject().put("role", role).put("content", content)))
            if(role == "user" && getString("title") == "新的对话") put("title", content.take(20))
        } else chat })
    }
    fun send(text: String, images: List<ByteArray> = emptyList()) {
        if(aiBusy.value || (text.isBlank() && images.isEmpty())) return
        val id = selectedConversation.value.ifBlank { newConversation() }; val user = text.ifBlank { "请分析图片" }
        append(id, "user", user); aiBusy.value = true; proposal.value = null
        viewModelScope.launch {
            try {
                val original = snapshot.value
                val context = Merge.wire(original).put("favorites", JSONArray(original.records.filter { it.type == RecordType.FAVORITE }.map { it.json })).put("exerciseTemplates", JSONArray(original.records.filter { it.type == RecordType.EXERCISE }.map { it.json }))
                val c = config.value.copy()
                val history = conversations.value.first { it.getString("id") == id }.getJSONArray("messages").objects()
                val reply = withContext(Dispatchers.IO) { parseObject(app.network.complete(c, app.secrets.get("ai.${c.getString("provider")}"), AgentActions.PROMPT + "\n本地时间：${OffsetDateTime.now()}\n当前数据：$context", history, images, true)) }
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
