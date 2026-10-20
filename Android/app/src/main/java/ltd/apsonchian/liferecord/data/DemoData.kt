package ltd.apsonchian.liferecord.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalTime
import java.util.UUID
import kotlin.math.sin

/** Synthetic local examples. Their flags must survive edits and never reach sync. */
object DemoData {
    fun records(at: Double = now()): List<Record> = buildList {
        for (offset in 29 downTo 0) {
            val day = at.day().minusDays(offset.toLong())
            fun time(hour: Int, minute: Int = 0) = minOf(day.epochAt(LocalTime.of(hour, minute)), at)
            fun record(type: RecordType, date: Double, configure: JSONObject.() -> Unit): Record =
                Record.create(type, date).apply { json.put("isDemo", true); json.configure() }
            val progress = (29 - offset).toDouble()
            if (offset != 9 && offset != 18) add(record(RecordType.BODY, time(7, 20)) {
                put("weight", 64 + progress * .035 + sin(offset / 3.4) * .18)
                if (offset % 4 != 1) put("bodyFat", 14.6 - progress * .012)
                if (offset % 3 == 0) put("waist", 76 - progress * .018)
                put("note", "[示例] 晨起测量 · 数值仅用于体验")
            })
            val trainingDay = offset % 3 != 2
            if (offset != 11) {
                fun meal(kind: String, name: String, hour: Int, protein: Double, carbs: Double, fat: Double, fiber: Double) {
                    add(record(RecordType.MEAL, time(hour)) {
                        put("kind", kind); put("name", name); put("protein", protein); put("carbs", carbs)
                        put("fat", fat); put("fiber", fiber); put("calories", protein * 4 + carbs * 4 + fat * 9)
                        put("note", "[示例] 合成餐食，可点开查看营养明细")
                    })
                }
                meal("早餐", if (offset % 2 == 0) "燕麦鸡蛋牛奶碗" else "全麦面包煎蛋", 8, 34.0, 64.0, 15.0, 8.0)
                meal("午餐", if (offset % 2 == 0) "鸡胸肉糙米饭" else "虾仁杂粮饭", 12, if (trainingDay) 52.0 else 45.0, if (trainingDay) 88.0 else 72.0, 19.0, 7.0)
                if (offset != 10) meal("晚餐", if (offset % 2 == 0) "三文鱼藜麦沙拉" else "鸡腿红薯西兰花", 19, 47.0, 58.0, 24.0, 10.0)
                if (trainingDay) meal("加餐", "酸奶蓝莓坚果", 16, 22.0, 33.0, 10.0, 5.0)
            }
            if (trainingDay) {
                val end = time(18, 50)
                add(record(RecordType.WORKOUT, end - (40 + offset % 4 * 5) * 60) {
                    put("endDate", end)
                    val strength = offset % 3 == 0
                    put("bodyParts", JSONArray(if (strength) listOf("胸部", "三头") else listOf("有氧", "核心")))
                    fun exercise(name: String, part: String, sets: List<JSONObject>) = JSONObject().put("name", name).put("bodyPart", part).put("sets", JSONArray(sets))
                    put("exercises", JSONArray(if (strength) listOf(
                        exercise("哑铃卧推", "胸部", (0..2).map { JSONObject().put("reps", 12 - it * 2).put("weight", 12 + (29 - offset) / 10 * 2) }),
                        exercise("绳索下压", "三头", listOf(JSONObject().put("reps", 12).put("weight", 15), JSONObject().put("reps", 10).put("weight", 15)))
                    ) else listOf(
                        exercise("椭圆机", "有氧", listOf(JSONObject().put("durationSeconds", 1800))),
                        exercise("平板支撑", "核心", listOf(JSONObject().put("durationSeconds", 45), JSONObject().put("durationSeconds", 40)))
                    )))
                    put("note", if (strength) "[示例] 力量训练 · 查看动作与逐组记录" else "[示例] 有氧与核心 · 查看计时记录")
                })
            }
        }
    }

    fun conversations(at: Double = now()): List<JSONObject> {
        fun chat(title: String, question: String, answer: String, timestamp: Double) = JSONObject()
            .put("id", UUID.randomUUID().toString()).put("title", "[示例] $title").put("isDemo", true)
            .put("messages", JSONArray(listOf(
                CoachGeneration.question(question, question, emptyList(), timestamp - 60).put("generationState", "completed"),
                JSONObject().put("id", UUID.randomUUID().toString()).put("role", "assistant").put("content", answer).put("createdAt", timestamp)
            )))
        return listOf(
            chat("看懂一个月的记录", "这些趋势和训练记录怎么看？", "这是预先写好的示例回答，不是实时 AI 分析。\n\n在「趋势」切换近 7 天或近 30 天，查看体重、体脂、每日热量与训练时长。点进训练日历，可以查看部位、动作和每组记录。空白日期表示未记录。\n\n这些都是合成数据，不代表你的身体情况，也不计入真实目标反馈或 AI 周报。", at),
            chat("从第一餐开始", "我该怎样开始记录？", "这是预先写好的使用示例。\n\n1. 在「今日」点添加，手动记一餐或一次测量。\n2. 训练时点「开始训练」，结束后可补充动作和组数。\n3. 在「设置」填写自己的目标，需要时再连接同步与 AI 服务。\n\n示例可随时在设置中清除；清除后，你自己的记录会保留。", at - 120)
        )
    }
}
