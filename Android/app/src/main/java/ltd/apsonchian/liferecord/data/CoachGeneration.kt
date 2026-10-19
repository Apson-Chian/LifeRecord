package ltd.apsonchian.liferecord.data

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

object CoachGeneration {
    fun question(content: String, displayText: String, photos: List<String>, timestamp: Double = now()): JSONObject =
        JSONObject().put("id", UUID.randomUUID().toString()).put("role", "user")
            .put("content", content).put("displayText", displayText).put("localPhotoFiles", JSONArray(photos))
            .put("createdAt", timestamp).put("generationState", "pending")

    fun update(chats: List<JSONObject>, conversation: String, message: String, state: String, reason: String = ""): List<JSONObject> =
        chats.map { chat ->
            if(chat.optString("id") != conversation) chat else chat.copy().apply {
                put("messages", JSONArray(getJSONArray("messages").objects().map { original ->
                    if(original.optString("id") == message) original.copy().put("generationState", state).put("generationError", reason) else original
                }))
            }
        }

    fun recover(chats: List<JSONObject>): List<JSONObject> = chats.map { chat -> chat.copy().apply {
        put("messages", JSONArray(getJSONArray("messages").objects().map { message ->
            when(message.optString("generationState")) {
                "pending" -> message.copy().put("generationState", "failed").put("generationError", "上次生成中断，可以重新生成。")
                "applying" -> message.copy().put("generationState", "needsReview").put("generationError", "上次处理记录时中断，请先核对记录，再决定是否重新发送。")
                else -> message
            }
        }))
    } }

    fun retryable(messages: List<JSONObject>): JSONObject? = messages.lastOrNull { it.optString("role") == "user" }?.takeIf {
        it.optString("generationState") == "failed" && it.optString("id").isNotBlank() && it.optDouble("createdAt") > 0
    }

    fun history(messages: List<JSONObject>, messageID: String): List<JSONObject> {
        val index = messages.indexOfFirst { it.optString("id") == messageID && it.optString("role") == "user" }
        require(index >= 0) { "原问题已不存在，请重新发送" }
        return messages.take(index + 1).filter {
            it.optString("role") in listOf("user", "assistant") && !(it.optString("role") == "assistant" &&
                (it.optString("content").startsWith("回答失败：") || it.optString("content").startsWith("已停止生成，")))
        }.map { it.copy() }
    }
}
