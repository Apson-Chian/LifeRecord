package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime

class BodyOverviewTest {
    private val day=LocalDate.parse("2026-10-19")
    private fun measurement(date:LocalDate,weight:Double,fat:Double?=null)=Record.create(RecordType.BODY,date.epochAt(LocalTime.of(8,0))).apply {json.put("weight",weight);if(fat!=null) json.put("bodyFat",fat)}
    @Test fun medianAndCompositionUseOriginalPairedValues() {
        val first=measurement(day,70.0,20.0);val second=measurement(day,72.0)
        val result=BodyOverview.summarize(listOf(first,second),day.epochAt(LocalTime.NOON))
        assertEquals(71.0,result.today!!.value,0.0);assertEquals(2,result.today!!.count)
        assertEquals(14.0,result.fatMass!!,0.0);assertEquals(56.0,result.leanMass!!,0.0)
    }
    @Test fun missingDemoFutureAndInvalidMeasurementsDoNotInventComposition() {
        val demo=measurement(day,70.0,20.0).apply {json.put("isDemo",true)}
        val future=measurement(day.plusDays(1),70.0,20.0)
        val valid=measurement(day,71.0,999.0)
        val result=BodyOverview.summarize(listOf(demo,future,valid),day.epochAt(LocalTime.NOON))
        assertEquals(1,result.points.size);assertNull(result.composition);assertNull(result.weeklyRate);assertNull(result.change7)
    }
    @Test fun weeklyRateUsesCalendarDaysAcrossIrregularMeasurements() {
        val values=listOf(0L,7L,14L).map {measurement(day.minusDays(14-it),70.0+it*.1)}
        val result=BodyOverview.summarize(values,day.epochAt(LocalTime.NOON))
        assertTrue(result.weeklyRate!!>0);assertTrue(result.change7!!>0)
    }
}
