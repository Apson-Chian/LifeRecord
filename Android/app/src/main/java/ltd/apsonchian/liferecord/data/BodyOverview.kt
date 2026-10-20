package ltd.apsonchian.liferecord.data

import java.time.LocalDate

data class BodyOverview(
    val points: List<BodyTrend.Point>, val today: BodyTrend.Point?,
    val change7: Double?, val change30: Double?, val weeklyRate: Double?, val composition: Record?
) {
    val fatMass: Double? get() = composition?.let { it.json.getDouble("weight") * it.json.getDouble("bodyFat") / 100 }
    val leanMass: Double? get() = composition?.let { it.json.getDouble("weight") - fatMass!! }
    companion object {
        fun summarize(records: List<Record>, at: Double = now(), includeDemo: Boolean = false): BodyOverview {
            val today=at.day()
            val valid=records.filter { it.type==RecordType.BODY && (includeDemo || !it.demo) && it.date<=at && RecordQuality.validWeight(it) }
            val points=BodyTrend.records(valid,"weight",at,includeDemo=includeDemo)
            val latest=points.lastOrNull()
            fun change(days:Long):Double? = latest?.let { last -> points.lastOrNull { it.day<=today.minusDays(days) }?.let { last.trend-it.trend } }
            val recent=points.filter { it.day>=today.minusDays(30) }.let { if(it.size>=3) it else points }
            val rate=if(recent.size>=3) {
                val meanX=recent.map { it.day.toEpochDay().toDouble() }.average();val meanY=recent.map { it.trend }.average()
                val denominator=recent.sumOf { val dx=it.day.toEpochDay()-meanX;dx*dx }
                if(denominator>0) recent.sumOf {(it.day.toEpochDay()-meanX)*(it.trend-meanY)}/denominator*7 else null
            } else null
            val paired=valid.filter { it.json.has("bodyFat") && !it.json.isNull("bodyFat") && it.json.optDouble("bodyFat") in 1.0..80.0 }
            val composition=paired.filter { it.date.day()==today }.minByOrNull { it.date } ?: paired.maxByOrNull { it.date }
            return BodyOverview(points,points.firstOrNull {it.day==today},change(7),change(30),rate,composition)
        }
    }
}
