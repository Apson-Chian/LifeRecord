package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import org.json.*
import org.junit.Assert.*
import org.junit.Test
import java.time.*

class WorkoutCalendarTest {
    private val zone=ZoneId.of("America/New_York")
    private fun stamp(date:String)=LocalDateTime.parse(date).atZone(zone).toEpochSecond().toDouble()
    private val at=stamp("2026-10-15T12:00")
    private fun session(start:String,end:String?=null,sets:JSONArray=JSONArray())=Record.create(RecordType.WORKOUT,stamp(start)).apply {
        end?.let {json.put("endDate",stamp(it))}
        json.put("exercises",JSONArray().put(JSONObject().put("name","划船").put("sets",sets)))
    }
    @Test fun mondayGridUsesWholeWeeksIncludingAdjacentMonthsAndLeapDay() {
        val october=WorkoutCalendar.month(YearMonth.of(2026,10),emptyList(),at,zone)
        assertEquals(LocalDate.of(2026,9,28),october.days.first().date);assertEquals(35,october.days.size)
        assertEquals(31,october.days.count {it.inMonth});assertEquals(DayOfWeek.SUNDAY,october.days.last().date.dayOfWeek)
        assertEquals(29,WorkoutCalendar.month(YearMonth.of(2028,2),emptyList(),at,zone).days.count {it.inMonth})
    }
    @Test fun crossMidnightBelongsToStartDayAndOnlyCompletedSessionsCount() {
        val records=listOf(session("2026-10-01T23:30","2026-10-02T01:30"),session("2026-10-02T09:00"),session("2026-10-16T09:00","2026-10-16T10:00"),session("2026-09-30T23:30","2026-10-01T01:30"),session("2026-10-03T10:00","2026-10-03T09:00"))
        val month=WorkoutCalendar.month(YearMonth.of(2026,10),records,at,zone)
        assertEquals(1,month.recordedDays);assertEquals(1,month.completedCount);assertEquals(120.0,month.minutes,0.0)
        assertEquals(1,month.days.single {it.date==LocalDate.of(2026,10,1)}.sessions.size)
        assertTrue(month.days.single {it.date==LocalDate.of(2026,10,2)}.completed.isEmpty())
    }
    @Test fun missingLoadsAreNotGuessedAndZeroIsDistinctFromUnknown() {
        val sets=JSONArray().put(JSONObject().put("weight",20).put("reps",8)).put(JSONObject().put("weight",25).put("reps",10))
            .put(JSONObject().put("weight",0).put("reps",12)).put(JSONObject().put("reps",8)).put(JSONObject().put("weight",50))
        val r=session("2026-10-01T09:00","2026-10-01T10:00",sets)
        assertEquals(410.0,WorkoutCalendar.volume(r)!!,0.0)
        assertNull(WorkoutCalendar.volume(session("2026-10-02T09:00","2026-10-02T10:00")))
        assertEquals(410.0,WorkoutCalendar.month(YearMonth.of(2026,10),listOf(r),at,zone).days.single {it.date.dayOfMonth==1 && it.inMonth}.volume!!,0.0)
    }
    @Test fun daylightSavingDurationUsesInstantsNotWallClockSubtraction() {
        val r=session("2026-03-08T01:30","2026-03-08T03:30")
        val month=WorkoutCalendar.month(YearMonth.of(2026,3),listOf(r),at,zone)
        assertEquals(60.0,month.minutes,0.0);assertEquals(1,month.completedCount)
    }
    @Test fun detailRetainsPartsNotesAndAllSetsWhileDeletedRowsAreHidden() {
        val r=session("2026-10-01T09:00","2026-10-01T10:00",JSONArray().put(JSONObject().put("weight",40).put("reps",8))).apply {json.put("bodyParts",JSONArray().put("背部"));json.put("note","完整动作记录")}
        assertTrue(WorkoutCalendar.content(r).contains("40 kg × 8 次"));assertTrue(WorkoutCalendar.content(r).contains("背部"));assertEquals("背部",WorkoutCalendar.title(r))
        r.json.put("isDeleted",true)
        assertEquals(0,WorkoutCalendar.month(YearMonth.of(2026,10),listOf(r),at,zone).completedCount)
    }
}
