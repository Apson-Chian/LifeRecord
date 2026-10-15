package ltd.apsonchian.liferecord.service

import org.json.JSONObject

object CoachPolicy {
    fun mutationRequest(text: String): Boolean {
        val compact=text.filterNot { it.isWhitespace() }
        return compact.startsWith("记录") || listOf("帮我记录","帮我记","记录一下","记一下","记到","记入","录入","登记","保存","新增","添加","修改","改成","更新目标","设置为","删掉","删除","移除").any { it in compact }
    }
    fun blocked(reply: JSONObject, allowed: Boolean, request: String): String? = if(!allowed && ((reply.optJSONArray("actions")?.length() ?: 0)>0 || mutationRequest(request))) "未保存：当前未开启 AI 写入。请打开输入框上方的“允许 AI 修改记录”，再发送这条记录请求。" else null
}
