package ltd.apsonchian.liferecord.data

import java.time.*

/** Calendar days use the session's local start day, including sessions crossing midnight. */
object WorkoutCalendar {
    data class Day(val date: LocalDate, val inMonth: Boolean, val sessions: List<Record>, val completed: List<Record>) {
        val minutes get() = completed.sumOf { (it.json.getDouble("endDate") - it.date) / 60 }
        val volume get() = completed.mapNotNull(::volume).takeIf { it.isNotEmpty() }?.sum()?.takeIf { it.isFinite() }
    }
    data class Month(val start: YearMonth, val days: List<Day>) {
        val recordedDays get() = days.count { it.inMonth && it.completed.isNotEmpty() }
        val completedCount get() = days.filter { it.inMonth }.sumOf { it.completed.size }
        val minutes get() = days.filter { it.inMonth }.sumOf { it.minutes }
    }
    fun completed(record: Record, at: Double) = !record.json.isNull("endDate") && record.date <= at && record.json.optDouble("endDate") in record.date..at
    fun volume(record: Record): Double? {
        val loads = record.json.optJSONArray("exercises")?.objects().orEmpty().flatMap { it.optJSONArray("sets")?.objects().orEmpty() }.mapNotNull {
            val weight = it.optDouble("weight", Double.NaN); val reps = it.optDouble("reps", Double.NaN)
            (weight * reps).takeIf { load -> weight.isFinite() && weight > 0 && reps.isFinite() && reps > 0 && load.isFinite() }
        }
        return loads.takeIf { it.isNotEmpty() }?.sum()?.takeIf { it.isFinite() }
    }
    fun title(record: Record): String = record.json.optJSONArray("bodyParts")?.strings().orEmpty().joinToString("+").ifBlank {
        record.json.optString("note").trim().ifBlank { record.json.optJSONArray("exercises")?.objects().orEmpty().map { it.optString("name") }.filter { it.isNotBlank() }.joinToString("+").ifBlank { "未填写训练内容" } }
    }
    fun content(record: Record): String = buildList {
        record.json.optJSONArray("bodyParts")?.strings()?.joinToString(" · ")?.takeIf { it.isNotBlank() }?.let(::add)
        record.json.optString("note").takeIf { it.isNotBlank() }?.let(::add)
        record.json.optJSONArray("exercises")?.objects().orEmpty().forEach { exercise ->
            add(exercise.optString("name") + exercise.optJSONArray("sets")?.objects().orEmpty().mapIndexed { i, set ->
                "\n  ${i+1}. " + listOfNotNull(set.optDouble("weight",Double.NaN).takeIf { it.isFinite() }?.let { "${format(it)} kg" },set.optDouble("reps",Double.NaN).takeIf { it.isFinite() }?.let { "${format(it)} 次" },set.optDouble("durationSeconds",Double.NaN).takeIf { it.isFinite() }?.let { "${format(it)} 秒" }).joinToString(" × ").ifBlank { "未填写数值" }
            }.joinToString(""))
        }
    }.joinToString("\n").ifBlank { "未填写训练内容" }
    fun month(month: YearMonth, records: List<Record>, at: Double = now(), zone: ZoneId = ZoneId.systemDefault()): Month {
        val first = month.atDay(1); val offset = first.dayOfWeek.value - 1
        val start = first.minusDays(offset.toLong()); val count = ((offset + month.lengthOfMonth() + 6) / 7) * 7
        val grouped = records.filter { it.type == RecordType.WORKOUT && !it.json.optBoolean("isDeleted") }.groupBy { Instant.ofEpochMilli((it.date * 1000).toLong()).atZone(zone).toLocalDate() }
        return Month(month, (0 until count).map { index ->
            val day = start.plusDays(index.toLong()); val sessions = grouped[day].orEmpty().sortedWith(compareBy<Record> { it.date }.thenBy { it.id })
            Day(day, YearMonth.from(day) == month, sessions, sessions.filter { completed(it, at) })
        })
    }
}
