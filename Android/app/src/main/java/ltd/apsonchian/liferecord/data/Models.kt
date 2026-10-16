package ltd.apsonchian.liferecord.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.*
import java.util.UUID

fun now() = System.currentTimeMillis() / 1000.0
fun JSONObject.copy() = JSONObject(toString())
fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }
fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }
fun Double.day(): LocalDate = Instant.ofEpochMilli((this * 1000).toLong()).atZone(ZoneId.systemDefault()).toLocalDate()
fun LocalDate.epochAt(time: LocalTime = LocalTime.now()): Double = atTime(time).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli() / 1000.0
val parts = listOf("胸部", "背部", "肩部", "二头", "三头", "小臂", "核心", "臀腿", "全身", "有氧", "其他")
val kinds = listOf("早餐", "午餐", "晚餐", "加餐")
enum class RecordType(val wire: String, val collection: String, val label: String) {
    MEAL("meal", "meals", "餐食"), BODY("body", "bodyMetrics", "身体测量"), WORKOUT("workout", "workoutEntries", "训练"),
    FAVORITE("favorite", "favorites", "常用餐食"), EXERCISE("exercise", "exerciseTemplates", "动作")
}
data class Record(val type: RecordType, val json: JSONObject) {
    val id: String get() = json.getString("id")
    val date: Double get() = json.optDouble("date", now())
    val updated: Double get() = json.getDouble("updatedAt")
    val demo: Boolean get() = json.optBoolean("isDemo")
    val title: String get() = when(type) {
        RecordType.BODY -> "${format(json.optDouble("weight"))} kg"
        RecordType.WORKOUT -> json.optJSONArray("bodyParts")?.strings()?.joinToString(" · ")?.ifBlank { "训练" } ?: "训练"
        else -> json.optString("name")
    }
    fun copy() = Record(type, json.copy())
    companion object {
        fun create(type: RecordType, date: Double = now()) = Record(type, JSONObject().apply {
            put("id", UUID.randomUUID().toString()); put("date", date); put("updatedAt", now()); put("createdAt", now()); put("note", "")
            when(type) {
                RecordType.MEAL, RecordType.FAVORITE -> { put("name", ""); put("kind", "午餐"); put("source", "手动"); put("photoIDs", JSONArray()); put("inputText", ""); listOf("calories", "protein", "carbs", "fat", "fiber").forEach { put(it, 0.0) } }
                RecordType.BODY -> put("weight", 65.0)
                RecordType.WORKOUT -> { put("endDate", JSONObject.NULL); put("bodyParts", JSONArray()); put("exercises", JSONArray()) }
                RecordType.EXERCISE -> { put("name", ""); put("bodyPart", "胸部"); put("sets", 3) }
            }
        })
    }
}
fun format(value: Double): String = if (value % 1.0 == 0.0) value.toLong().toString() else String.format(java.util.Locale.ROOT, "%.1f", value)
fun defaultProfile() = JSONObject().apply {
    put("id", "profile"); put("updatedAt", 1.0); put("displayName", ""); put("fitnessGoal", "维持")
    put("height", 170.0); put("baselineWeight", 70.0); put("targetWeight", 70.0); put("weeklyWeightTarget", 0.0)
    put("calorieGoal", 2000.0); put("proteinGoal", 100.0); put("carbsGoal", 250.0); put("fatGoal", 60.0)
}
object Validation {
    fun number(json: JSONObject, key: String, low: Double, high: Double, optional: Boolean = false) {
        if (optional && (!json.has(key) || json.isNull(key))) return
        val value = json.optDouble(key, Double.NaN)
        require(value.isFinite() && value in low..high) { "$key 应在 ${format(low)}–${format(high)} 之间" }
    }
    fun record(r: Record) {
        val j = r.json
        require(r.id.isNotBlank() && r.id.length <= 80); number(j, "date", 0.0, 4102444800.0)
        when(r.type) {
            RecordType.MEAL, RecordType.FAVORITE -> {
                require(j.optString("name").isNotBlank()) { "请填写餐食名称" }
                require(j.optString("kind", "加餐") in kinds) { "请选择餐次" }
                val ids = j.optJSONArray("photoIDs")?.strings().orEmpty()
                require(ids.size <= 12 && ids.all { it.matches(Regex("[0-9a-f]{32}")) }) { "照片编号无效" }
                listOf("calories" to 20000.0, "protein" to 2000.0, "carbs" to 3000.0, "fat" to 2000.0, "fiber" to 500.0).forEach { (key, max) -> number(j, key, 0.0, max) }
            }
            RecordType.BODY -> { number(j, "weight", 20.0, 400.0); number(j, "bodyFat", 0.0, 75.0, true); number(j, "waist", 20.0, 300.0, true) }
            RecordType.WORKOUT -> {
                number(j, "endDate", r.date, 4102444800.0, true)
                val bodyParts = j.optJSONArray("bodyParts")?.strings().orEmpty()
                require(bodyParts.size <= 30 && bodyParts.distinct().size == bodyParts.size && bodyParts.all(WorkoutParts::valid)) { "请检查训练部位" }
                val exercises = j.optJSONArray("exercises")?.objects().orEmpty()
                require(exercises.size <= 50) { "最多 50 个动作" }
                exercises.forEach { ex ->
                    require(ex.optString("name").isNotBlank() && ex.getString("name").length <= 100) { "请填写动作名称" }
                    val sets = ex.getJSONArray("sets").objects(); require(sets.size <= 100)
                    sets.forEach { s -> number(s, "reps", 1.0, 10000.0, true); number(s, "weight", 0.0, 2000.0, true); number(s, "durationSeconds", 1.0, 86400.0, true)
                        listOf("reps", "durationSeconds").forEach { key -> if (!s.isNull(key) && s.has(key)) require(s.getDouble(key) % 1.0 == 0.0) { "次数和秒数需要整数" } }
                    }
                }
            }
            RecordType.EXERCISE -> require(j.optString("name").isNotBlank()) { "请填写动作名称" }
        }
    }
    fun profile(j: JSONObject) {
        require(j.optString("fitnessGoal") in listOf("增肌", "减脂", "维持")) { "请选择健身目标" }
        number(j, "height", 80.0, 250.0); number(j, "baselineWeight", 20.0, 400.0); number(j, "targetWeight", 20.0, 400.0)
        number(j, "weeklyWeightTarget", -2.0, 2.0)
        listOf("calorieGoal", "proteinGoal", "carbsGoal", "fatGoal").forEach { number(j, it, 1.0, if(it == "calorieGoal") 20000.0 else 3000.0) }
    }
}
data class Snapshot(val records: List<Record>, val profile: JSONObject, val deletions: List<JSONObject>)
object Merge {
    fun apply(local: Snapshot, remote: JSONObject): Snapshot {
        val records = local.records.associateBy { it.type.wire + ":" + it.id.lowercase() }.toMutableMap()
        val tombs = local.deletions.associateBy { it.getString("recordType") + ":" + it.getString("id").lowercase() }.toMutableMap()
        remote.optJSONArray("deletions")?.objects()?.forEach { d ->
            val key = d.getString("recordType") + ":" + d.getString("id").lowercase()
            if (d.getDouble("deletedAt") >= (tombs[key]?.optDouble("deletedAt") ?: 0.0)) tombs[key] = d.copy()
        }
        listOf(RecordType.MEAL, RecordType.BODY, RecordType.WORKOUT).forEach { type ->
            remote.optJSONArray(type.collection)?.objects()?.forEach { j ->
                val r = Record(type, j.copy()); Validation.record(r)
                val key = type.wire + ":" + r.id.lowercase()
                if (r.updated > (records[key]?.updated ?: 0.0)) {
                    records[key]?.let { old -> listOf("localPhotoFiles", "uploadedPhotoFiles").forEach { field -> if(old.json.has(field)) r.json.put(field, old.json.get(field)) } }
                    records[key] = r
                }
            }
        }
        tombs.forEach { (key, d) -> if ((records[key]?.updated ?: Double.MAX_VALUE) <= d.getDouble("deletedAt")) records.remove(key) }
        val profile = remote.optJSONObject("settings")?.takeIf { it.optDouble("updatedAt") > local.profile.optDouble("updatedAt") }?.also { Validation.profile(it) } ?: local.profile
        return Snapshot(records.values.toList(), profile.copy(), tombs.values.toList())
    }
    fun wire(s: Snapshot) = JSONObject().apply {
        listOf(RecordType.MEAL, RecordType.BODY, RecordType.WORKOUT).forEach { type -> put(type.collection, JSONArray(s.records.filter { it.type == type && !it.demo }.map { it.json.copy().apply { remove("isDemo"); remove("localPhotoFiles"); remove("uploadedPhotoFiles") } })) }
        put("settings", s.profile); put("deletions", JSONArray(s.deletions))
    }
}
object Insights {
    fun daily(records: List<Record>, day: LocalDate) = records.filter { it.type == RecordType.MEAL && it.date.day() == day }
    fun total(records: List<Record>, key: String) = records.sumOf { it.json.optDouble(key, 0.0) }
    fun streak(records: List<Record>, today: LocalDate = LocalDate.now()): Int {
        val days = records.filter { !it.demo && it.type in listOf(RecordType.MEAL, RecordType.BODY, RecordType.WORKOUT) && it.date <= now() && it.date.day() <= today }.map { it.date.day() }.toSet()
        var day = if (today in days) today else today.minusDays(1); var count = 0
        while(day in days) { count++; day = day.minusDays(1) }; return count
    }
    fun weights(records: List<Record>): List<Pair<LocalDate, Double>> = records.filter { it.type == RecordType.BODY && !it.demo && it.date <= now() }
        .groupBy { it.date.day() }.toSortedMap().map { (date, values) ->
            val sorted = values.map { it.json.getDouble("weight") }.sorted(); val mid = sorted.size / 2
            date to if(sorted.size % 2 == 1) sorted[mid] else (sorted[mid - 1] + sorted[mid]) / 2
        }
    fun quality(r: Record): List<String> = buildList {
        if (r.demo) return@buildList
        if (r.date > now() + 300) add("记录时间在未来，请核对")
        if(r.type == RecordType.MEAL) {
            val macro = r.json.optDouble("protein")*4 + r.json.optDouble("carbs")*4 + r.json.optDouble("fat")*9
            val calories = r.json.optDouble("calories")
            if(kotlin.math.abs(macro-calories) > maxOf(100.0, calories*0.3)) add("热量与宏量营养换算有较大差异")
        }
        if(r.type == RecordType.WORKOUT && !r.json.isNull("endDate") && r.json.optDouble("endDate") - r.date > 21600) add("训练超过六小时，请核对起止时间")
    }
}
