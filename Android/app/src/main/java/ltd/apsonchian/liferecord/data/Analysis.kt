package ltd.apsonchian.liferecord.data

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.pow
import org.json.JSONObject

/** Same daily median and elapsed-day exponential smoothing as iOS BodyTrend. */
object BodyTrend {
    data class Sample(val date: Double, val value: Double)
    data class Point(val day: LocalDate, val value: Double, val trend: Double, val count: Int)
    fun series(samples: List<Sample>): List<Point> {
        val result = mutableListOf<Point>()
        samples.filter { it.value.isFinite() && it.value > 0 }.groupBy { it.date.day() }.toSortedMap().forEach { (day, entries) ->
            val values = entries.map { it.value }.sorted(); val middle = values.size / 2
            val median = if(values.size % 2 == 0) (values[middle - 1] + values[middle]) / 2 else values[middle]
            val previous = result.lastOrNull()
            val alpha = if(previous == null) 1.0 else 1 - 0.9.pow(ChronoUnit.DAYS.between(previous.day, day).coerceAtLeast(1).toDouble())
            result += Point(day, median, previous?.let { it.trend + alpha * (median - it.trend) } ?: median, values.size)
        }
        return result
    }
    fun records(records: List<Record>, field: String, at: Double = now()): List<Point> = series(records.filter {
        it.type == RecordType.BODY && !it.demo && it.date <= at && !it.json.isNull(field) &&
            (if(field == "weight") RecordQuality.validWeight(it) else it.json.optDouble(field) in 1.0..80.0)
    }.map { Sample(it.date, it.json.optDouble(field)) })
}

/** Analysis produces versioned hints; confirmation never changes the source records. */
object RecordQuality {
    enum class Kind { duplicateMeal, nutrition, uncertainAI, bodyValue, weightJump, workoutTime, futureDate }
    data class Issue(val id: String, val kind: Kind, val type: RecordType, val recordIDs: List<String>, val date: Double, val title: String, val detail: String)
    private val nutritionFields = listOf("calories", "protein", "carbs", "fat", "fiber")
    fun validNutrition(r: Record) = nutritionFields.all { r.json.optDouble(it).let { n -> n.isFinite() && n in 0.0..1_000_000.0 } }
    fun validWeight(r: Record) = r.json.optDouble("weight").let { it.isFinite() && it in 20.0..400.0 }
    private fun normalized(value: String) = value.lowercase(java.util.Locale.ROOT).filterNot { it.isWhitespace() }
    fun issues(records: List<Record>, at: Double = now()): List<Issue> {
        val result = mutableListOf<Issue>()
        fun add(kind: Kind, type: RecordType, entries: List<Record>, date: Double, title: String, detail: String) {
            val signature = entries.map { "${it.id.lowercase()}:${it.updated}" }.sorted().joinToString("|")
            result += Issue("${kind.name}:$signature", kind, type, entries.map { it.id }, date, title, detail)
        }
        val meals = records.filter { it.type == RecordType.MEAL && !it.demo }
        meals.forEach { r ->
            val j = r.json
            if(r.date > at + 300) add(Kind.futureDate, r.type, listOf(r), r.date, "餐食时间在未来", "核对这餐的日期和时间，未来记录不会计入目标反馈。")
            val energy = j.optDouble("protein") * 4 + j.optDouble("carbs") * 4 + j.optDouble("fat") * 9
            if(!validNutrition(r) || j.optDouble("calories") > 5000 || j.optDouble("protein") > 500 || j.optDouble("carbs") > 1500 || j.optDouble("fat") > 500 || j.optDouble("fiber") > 200) {
                add(Kind.nutrition, r.type, listOf(r), r.date, "营养数值需要核对", "${r.title}：检查份量、单位和小数点。单餐较大数值也可能正确，请自行确认。")
            } else if(energy > 0 && abs(j.optDouble("calories") - energy) > maxOf(150.0, j.optDouble("calories") * .4)) {
                add(Kind.nutrition, r.type, listOf(r), r.date, "热量与宏量营养差异较大", "${r.title}：宏量营养粗略换算与记录热量差异较大。纤维、酒精和标签算法可能带来差异，请核对原始信息。")
            }
            val name = normalized(r.title)
            val vague = name in listOf("食物", "餐食", "一餐", "午餐", "晚餐", "早餐", "加餐", "未知")
            val uncertain = listOf("份量不详", "份量不明", "无法确定", "待确认", "不确定").any { j.optString("note").contains(it) }
            if(j.optString("source").contains("AI", true) && (name.isEmpty() || vague || uncertain)) add(Kind.uncertainAI, r.type, listOf(r), r.date, "AI 估算信息不足", "${r.title}：补充食物名称、重量或实际吃下的份量，再核对营养数值。")
        }
        meals.filter { it.title.isNotBlank() && validNutrition(it) }.groupBy { "${it.json.optString("kind")}|${normalized(it.title)}" }.values.forEach { group ->
            val clusters = mutableListOf<MutableList<Record>>()
            group.sortedWith(compareBy<Record> { it.date }.thenBy { it.id }).forEach { meal ->
                var matching: MutableList<Record>? = null
                for(cluster in clusters.asReversed()) {
                    if(meal.date - cluster.first().date > 600) break
                    if(nutritionFields.all { abs(meal.json.optDouble(it) - cluster.first().json.optDouble(it)) < .01 }) { matching = cluster; break }
                }
                if(matching != null) matching.add(meal) else clusters.add(mutableListOf(meal))
            }
            clusters.filter { it.size > 1 }.forEach { cluster -> add(Kind.duplicateMeal, RecordType.MEAL, cluster, cluster.first().date, "疑似重复餐食 · ${cluster.size} 条", "${cluster.first().title}：10 分钟内名称、餐次和营养数值相同。可能是重复录入，也可能是多份，请逐条核对。") }
        }
        var previous: Record? = null
        records.filter { it.type == RecordType.BODY && !it.demo }.sortedWith(compareBy<Record> { it.date }.thenBy { it.id }).forEach { r ->
            if(r.date > at + 300) add(Kind.futureDate, r.type, listOf(r), r.date, "测量时间在未来", "核对测量日期，未来测量不会计入目标反馈。")
            if(!validWeight(r) || (!r.json.isNull("bodyFat") && r.json.optDouble("bodyFat").let { !it.isFinite() || it !in 1.0..80.0 })) add(Kind.bodyValue, r.type, listOf(r), r.date, "身体数值需要核对", "检查体重是否为 20–400 kg、体脂率是否为 1–80%，以及单位和小数点。")
            if(validWeight(r) && r.date <= at) {
                previous?.let { p -> if(r.date - p.date <= 3 * 86400 && abs(r.json.optDouble("weight") - p.json.optDouble("weight")) >= maxOf(3.0, p.json.optDouble("weight") * .05)) add(Kind.weightJump, r.type, listOf(p, r), r.date, "短期体重变化较大", "3 天内相邻测量相差至少 3 kg 且达到前次体重的 5%。核对时间、单位和测量条件；这不代表脂肪变化。") }
                previous = r
            }
        }
        records.filter { it.type == RecordType.WORKOUT && !it.demo }.forEach { r ->
            val end = r.json.takeUnless { it.isNull("endDate") }?.optDouble("endDate")
            if(r.date > at + 300 || (end != null && end > at + 300)) add(Kind.futureDate, r.type, listOf(r), r.date, "训练时间在未来", "核对训练起止时间，未来训练不会计入目标反馈。")
            if(end != null && (end < r.date || end - r.date > 6 * 3600)) add(Kind.workoutTime, r.type, listOf(r), r.date, "训练时长需要核对", "结束时间早于开始，或单次训练超过 6 小时。检查是否忘记结束计时；长时间活动也可能正确。")
            else if(end == null && at - r.date > 6 * 3600) add(Kind.workoutTime, r.type, listOf(r), r.date, "训练可能忘记结束", "这次训练已计时超过 6 小时，请填写实际结束时间。")
        }
        return result.sortedWith(compareByDescending<Issue> { it.date }.thenBy { it.id })
    }
}

object GoalFeedback {
    data class Period(val start: LocalDate, val end: LocalDate, val baseline: LocalDate, val change: Double, val targetChange: Double, val fraction: Double)
    data class Summary(val start: LocalDate, val end: LocalDate, val days: Int, val mealDays: Int, val calorieDays: Int, val proteinDays: Int,
        val calories: Double?, val protein: Double?, val measurementDays: Int, val latest: BodyTrend.Point?, val distance: Double?,
        val weeklyChange: Double?, val completedWorkouts: Int, val qualityCount: Int, val headline: String, val actions: List<String>, val period: Period?) {
        val context: String get() = "统计 $days 天；饮食记录 $mealDays 天，热量在设定目标 ±10% 内 $calorieDays 天，蛋白质达到设定目标 $proteinDays 天；已记录日均热量 ${calories?.let(::format) ?: "无记录"} kcal、蛋白质 ${protein?.let(::format) ?: "无记录"} g；测量 $measurementDays 天，最近趋势体重 ${latest?.trend?.let(::format) ?: "无记录"} kg，区间变化折算 ${weeklyChange?.let(::format) ?: "数据不足"} kg/周；完成训练 $completedWorkouts 次；区间内待核对 $qualityCount 项。反馈：$headline。下一步：${actions.joinToString("；")}。"
    }
    fun summarize(records: List<Record>, goals: JSONObject, range: Int, at: Double = now(), acknowledged: Set<String> = emptySet()): Summary {
        val today = at.day()
        val real = records.filter { !it.demo && it.date <= at }
        val meals = real.filter { it.type == RecordType.MEAL && RecordQuality.validNutrition(it) }
        val body = real.filter { it.type == RecordType.BODY && RecordQuality.validWeight(it) }
        val workouts = real.filter { it.type == RecordType.WORKOUT && !it.json.isNull("endDate") && it.json.optDouble("endDate") in it.date..at }
        val start = if(range > 0) today.minusDays(range.coerceAtLeast(1).toLong() - 1) else (meals + body + workouts).minByOrNull { it.date }?.date?.day() ?: today
        val days = ChronoUnit.DAYS.between(start, today).toInt().coerceAtLeast(0) + 1
        val nutrition = meals.filter { it.date.day() >= start }.groupBy { it.date.day() }.values.map { Insights.total(it, "calories") to Insights.total(it, "protein") }
        val calorieGoal = goals.optDouble("calorieGoal"); val proteinGoal = goals.optDouble("proteinGoal")
        val calorieValid = calorieGoal.isFinite() && calorieGoal > 0; val proteinValid = proteinGoal.isFinite() && proteinGoal > 0
        val series = BodyTrend.records(body, "weight", at); val latest = series.lastOrNull()
        val recent = series.filter { it.day >= start }; val rate = series.filter { it.day >= if(range == 7) today.minusDays(7) else start }
        val span = if(rate.size > 1) ChronoUnit.DAYS.between(rate.first().day, rate.last().day) else 0
        val weekly = if(span >= 7 && rate.size >= 3) (rate.last().trend - rate.first().trend) * 7 / span else null
        val baseline = goals.optDouble("baselineWeight"); val target = goals.optDouble("targetWeight"); val expected = goals.optDouble("weeklyWeightTarget")
        val mode = goals.optString("fitnessGoal"); val targetDelta = target - baseline
        val weightValid = baseline.isFinite() && target.isFinite() && baseline in 20.0..400.0 && target in 20.0..400.0
        val directionValid = mode == "维持" || (mode == "增肌" && targetDelta > 0 && expected >= 0) || (mode == "减脂" && targetDelta < 0 && expected <= 0)
        val configValid = weightValid && directionValid && expected.isFinite()
        val distance = if(weightValid) latest?.let { abs(it.trend - target) } else null
        val stale = latest?.let { ChronoUnit.DAYS.between(it.day, today) > 7 } ?: true
        val anchor = recent.firstOrNull()
        val period = if(mode != "维持" && configValid && !stale && abs(expected) > 0 && anchor != null && latest != null && latest.day > anchor.day) {
            val change = latest.trend - anchor.trend
            val targetChange = expected * ChronoUnit.DAYS.between(anchor.day, latest.day) / 7
            Period(start, today, anchor.day, change, targetChange, (change / targetChange).coerceIn(0.0, 1.0))
        } else null
        var headline = when {
            latest == null -> "先积累真实记录"
            stale -> "最近测量已超过 7 天"
            !configValid -> "请先核对身体目标"
            mode == "维持" -> if(distance!! <= .5) "接近设定的维持体重" else "与维持目标仍有差距"
            distance!! <= .2 -> "趋势体重已接近目标"
            weekly == null -> "已有测量，继续观察趋势"
            weekly * (if(target - latest.trend >= 0) 1 else -1) < -.05 -> "近期变化与目标方向相反"
            abs(weekly) < .05 -> "近期趋势变化较小"
            abs(expected) > 0 && abs(weekly) > abs(expected) + .1 -> "变化快于设定的每周节奏"
            else -> "正在向目标靠近"
        }
        val issues = RecordQuality.issues(records, at).filter { it.date.day() >= start && it.date <= at && it.id !in acknowledged }
        if(!stale && configValid && issues.any { it.kind in listOf(RecordQuality.Kind.bodyValue, RecordQuality.Kind.weightJump) }) headline = "身体记录待核对，先确认趋势"
        val actions = mutableListOf<String>()
        if(issues.isNotEmpty()) actions += "先到记录质量检查核对这段时间的 ${issues.size} 项疑点，再解读目标反馈。"
        if(stale) actions += "补充一次身体测量，再判断当前与目标的距离。"
        else if(weekly == null) actions += "在相近条件下继续测量；至少 3 个测量日、跨度 7 天后再比较每周节奏。"
        if(nutrition.size.toDouble() / days < .7) actions += "接下来优先连续记录每日餐食；缺失日期不会按零摄入计算。"
        else if(calorieValid && nutrition.any { abs(it.first - calorieGoal) > calorieGoal * .1 }) actions += "回看未落在热量目标 ±10% 内的日期，先确认餐食是否记全，再对照自己设定的份量计划。"
        if(proteinValid && nutrition.any { it.second < proteinGoal }) actions += "回看蛋白质未达到设定目标的日期，核对份量与漏记情况。"
        if(!configValid || (mode != "维持" && abs(targetDelta) < .2)) actions.add(0, "核对起始体重、目标体重与增肌/减脂方向是否一致。")
        if(!calorieValid || !proteinValid) actions.add(0, "核对每日热量和蛋白质目标，目标应为有效的正数。")
        if(actions.isEmpty()) actions += "继续按当前目标记录和执行，下周再比较趋势；不根据单日波动调整目标。"
        return Summary(start, today, days, nutrition.size, if(calorieValid) nutrition.count { abs(it.first - calorieGoal) <= calorieGoal * .1 } else 0,
            if(proteinValid) nutrition.count { it.second >= proteinGoal } else 0, nutrition.takeIf { it.isNotEmpty() }?.map { it.first }?.average(),
            nutrition.takeIf { it.isNotEmpty() }?.map { it.second }?.average(), recent.size, latest, distance, weekly, workouts.count { it.date.day() >= start }, issues.size, headline, actions.take(3), period)
    }
}
