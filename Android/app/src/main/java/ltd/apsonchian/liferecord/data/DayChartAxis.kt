package ltd.apsonchian.liferecord.data

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.floor
import kotlin.math.ceil
import kotlin.math.log10
import kotlin.math.pow

class DayChartAxis(start: LocalDate, end: LocalDate) {
    val first: LocalDate = minOf(start, end)
    val last: LocalDate = maxOf(start, end)
    val count: Long = ChronoUnit.DAYS.between(first, last) + 1
    fun fraction(day: LocalDate): Float = ((ChronoUnit.DAYS.between(first, day) + .5) / count).toFloat()
    fun dayAt(fraction: Float): LocalDate = first.plusDays(floor(fraction.coerceIn(0f, 1f) * count).toLong().coerceAtMost(count - 1))
    fun ticks(): List<LocalDate> {
        val total = minOf(4L, count).toInt()
        return (0 until total).map { first.plusDays(if(total == 1) 0 else (count - 1) * it / (total - 1)) }
    }
    fun label(day: LocalDate): String = day.format(DateTimeFormatter.ofPattern(if(first.year == last.year) "M/d" else "yy/M/d"))
    companion object {
        fun valueTicks(maximum: Double, goal: Double? = null): List<Double> {
            val upper=maxOf(maximum.takeIf {it.isFinite() && it>0} ?: 0.0,goal?.takeIf {it.isFinite() && it>0} ?: 0.0,1.0)*1.15
            val magnitude=10.0.pow(floor(log10(upper/3)))
            val scaled=upper/3/magnitude
            val step=magnitude*when {scaled<=1 -> 1;scaled<=2 -> 2;scaled<=5 -> 5;else -> 10}
            return (0..ceil(upper/step).toInt()).map {it*step}
        }
    }
}
