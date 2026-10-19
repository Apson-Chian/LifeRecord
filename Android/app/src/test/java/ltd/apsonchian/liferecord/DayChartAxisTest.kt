package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.DayChartAxis
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class DayChartAxisTest {
    @Test fun singleDayHasOneLabelAndSelectableEdges() {
        val day=LocalDate.parse("2026-10-19");val axis=DayChartAxis(day,day)
        assertEquals(listOf(day),axis.ticks());assertEquals(.5f,axis.fraction(day),0f)
        assertEquals(day,axis.dayAt(0f));assertEquals(day,axis.dayAt(1f))
    }
    @Test fun missingDaysKeepTheirSlotsAndLastDayIsVisible() {
        val start=LocalDate.parse("2026-10-01");val axis=DayChartAxis(start,start.plusDays(6))
        assertEquals(7L,axis.count);assertEquals(start.plusDays(2),axis.dayAt(2.5f/7))
        assertEquals(start.plusDays(6),axis.ticks().last());assertEquals(4,axis.ticks().distinct().size)
        assertTrue(axis.fraction(start)>0);assertTrue(axis.fraction(axis.last)<1)
    }
    @Test fun localDaysSurviveDstWithoutAssuming86400Seconds() {
        val zone=ZoneId.of("America/New_York")
        for(start in listOf(LocalDate.parse("2026-03-07"),LocalDate.parse("2026-10-31"))) {
            val axis=DayChartAxis(start,start.plusDays(2))
            assertEquals(3L,axis.count)
            assertEquals(start.plusDays(1),axis.dayAt(.5f))
            assertNotEquals(86400L,start.plusDays(2).atStartOfDay(zone).toEpochSecond()-start.plusDays(1).atStartOfDay(zone).toEpochSecond())
        }
    }
    @Test fun crossYearLabelsAreUnambiguous() {
        val axis=DayChartAxis(LocalDate.parse("2026-12-30"),LocalDate.parse("2027-01-02"))
        assertEquals("26/12/30",axis.label(axis.first));assertEquals("27/1/2",axis.label(axis.last))
    }
}
