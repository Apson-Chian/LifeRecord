package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime
import java.util.TimeZone

class AnalysisTest {
    private fun date(day:String,hour:Int=12)=LocalDate.parse(day).epochAt(LocalTime.of(hour,0))
    private val at get()=date("2026-10-14",22)
    private fun meal(day:String="2026-10-14",calories:Double=500.0)=Record.create(RecordType.MEAL,date(day)).apply {
        json.put("name","鸡肉米饭").put("calories",calories).put("protein",30).put("carbs",60).put("fat",15).put("fiber",4).put("updatedAt",1.0)
    }
    private fun body(day:String,weight:Double)=Record.create(RecordType.BODY,date(day)).apply { json.put("weight",weight).put("updatedAt",1.0) }
    @Test fun dailyMedianIgnoresInvalidSamplesAndSmoothsActualCalendarGap() {
        val samples=listOf(BodyTrend.Sample(date("2026-10-01",8),60.0),BodyTrend.Sample(date("2026-10-01",18),64.0),BodyTrend.Sample(date("2026-10-03"),66.0),BodyTrend.Sample(date("2026-10-03"),Double.NaN),BodyTrend.Sample(date("2026-10-03"),-1.0))
        val points=BodyTrend.series(samples.reversed())
        assertEquals(2,points.size);assertEquals(62.0,points[0].value,0.0);assertEquals(2,points[0].count)
        assertEquals(62.76,points[1].trend,1e-9)
    }
    @Test fun daylightSavingGapUsesCalendarDays() {
        val before=TimeZone.getDefault()
        try { TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
            val points=BodyTrend.series(listOf(BodyTrend.Sample(date("2026-03-07"),60.0),BodyTrend.Sample(date("2026-03-09"),70.0)))
            assertEquals(61.9,points.last().trend,1e-9)
        } finally { TimeZone.setDefault(before) }
    }
    @Test fun bodyChartFiltersDemoFutureAndInvalidWeightAndFat() {
        val records=listOf(body("2026-10-13",70.0),body("2026-10-15",72.0),body("2026-10-13",75.0).apply { json.put("isDemo",true) },body("2026-10-13",10.0))
        assertEquals(70.0,BodyTrend.records(records,"weight",at).single().value,0.0)
        val withFat=records.first().copy().apply { json.put("bodyFat",22.5) }
        assertEquals(22.5,BodyTrend.records(listOf(withFat),"bodyFat",at).single().value,0.0)
    }
    @Test fun duplicateClustersSearchPastDifferentNutritionAndRespectTenMinuteWindow() {
        val a=meal();val different=a.copy().apply { json.put("id","different").put("date",a.date+60).put("calories",501) }
        val b=a.copy().apply { json.put("id","second").put("date",a.date+120).put("name"," 鸡肉 米饭 ") }
        val late=a.copy().apply { json.put("id","late").put("date",a.date+601) }
        val issues=RecordQuality.issues(listOf(late,b,different,a),at).filter { it.kind==RecordQuality.Kind.duplicateMeal }
        assertEquals(1,issues.size);assertEquals(setOf(a.id,b.id),issues.single().recordIDs.toSet())
    }
    @Test fun qualityUsesIOSNutritionThresholdAndFlagsUncertainAI() {
        val uncertain=meal().apply { json.put("source","AI 估算").put("note","份量不详") }
        val large=meal(calories=6000.0)
        val issues=RecordQuality.issues(listOf(uncertain,large),at)
        assertTrue(issues.any { it.kind==RecordQuality.Kind.uncertainAI })
        assertTrue(issues.any { it.kind==RecordQuality.Kind.nutrition && large.id in it.recordIDs })
        assertFalse(RecordQuality.issues(listOf(meal()),at).any { it.kind==RecordQuality.Kind.nutrition })
    }
    @Test fun qualityChecksAdjacentValidBodyAndOngoingWorkouts() {
        val older=body("2026-10-12",60.0);val jump=body("2026-10-13",64.0)
        val ongoing=Record.create(RecordType.WORKOUT,date("2026-10-14",8))
        val issues=RecordQuality.issues(listOf(older,jump,ongoing),at)
        assertTrue(issues.any { it.kind==RecordQuality.Kind.weightJump && it.recordIDs==listOf(older.id,jump.id) })
        assertTrue(issues.any { it.kind==RecordQuality.Kind.workoutTime })
    }
    @Test fun futureDatesAreFlaggedAcrossAllThreeKindsAndDemoIsExcluded() {
        val future=meal("2026-10-15");val body=body("2026-10-15",70.0);val workout=Record.create(RecordType.WORKOUT,date("2026-10-15"))
        assertEquals(3,RecordQuality.issues(listOf(future,body,workout),at).count { it.kind==RecordQuality.Kind.futureDate })
        future.json.put("isDemo",true)
        assertTrue(RecordQuality.issues(listOf(future),at).isEmpty())
    }
    @Test fun acknowledgementIsOrderIndependentAndExpiresAfterRecordChange() {
        val a=meal();val b=a.copy().apply { json.put("id","other").put("date",a.date+60) }
        val old=RecordQuality.issues(listOf(a,b),at).single { it.kind==RecordQuality.Kind.duplicateMeal }
        assertEquals(old.id,RecordQuality.issues(listOf(b,a),at).single { it.kind==RecordQuality.Kind.duplicateMeal }.id)
        val edited=b.copy().apply { json.put("updatedAt",2.0) }
        assertNotEquals(old.id,RecordQuality.issues(listOf(a,edited),at).single { it.kind==RecordQuality.Kind.duplicateMeal }.id)
    }
    @Test fun coverageAndAveragesUseRecordedDaysAndExcludeFutureDemoInvalid() {
        val records=listOf(meal("2026-10-13"),meal("2026-10-14",1000.0),meal("2026-10-15"),meal().apply { json.put("isDemo",true) },meal().apply { json.put("calories","invalid") })
        val summary=GoalFeedback.summarize(records,defaultProfile(),7,at)
        assertEquals(7,summary.days);assertEquals(2,summary.mealDays);assertEquals(750.0,summary.calories!!,0.0)
    }
    @Test fun sevenDayRateUsesWeekOldAnchorAndThreeMeasurementDays() {
        val points=listOf(body("2026-10-07",70.0),body("2026-10-10",70.5),body("2026-10-14",71.0))
        assertNotNull(GoalFeedback.summarize(points,defaultProfile(),7,at).weeklyChange)
        assertNull(GoalFeedback.summarize(points.drop(1),defaultProfile(),7,at).weeklyChange)
    }
    @Test fun feedbackReviewsSelectedHistoricalRangeAndProratesMeasuredSpan() {
        val goals=defaultProfile().put("fitnessGoal","增肌").put("baselineWeight",70).put("targetWeight",75).put("weeklyWeightTarget",.5)
        val records=listOf(body("2026-10-01",70.0),body("2026-10-12",70.0),body("2026-10-14",70.4))
        val month=GoalFeedback.summarize(records,goals,30,at)
        val week=GoalFeedback.summarize(records,goals,7,at)
        assertEquals(at.day(),week.period!!.end)
        assertEquals(at.day().minusDays(6),week.period.start)
        assertEquals(LocalDate.parse("2026-10-12"),week.period.baseline)
        assertEquals(.5*2/7,week.period.targetChange,1e-9)
        assertEquals(.5*13/7,month.period!!.targetChange,1e-9)
        assertEquals(LocalDate.parse("2026-10-01"),month.period.baseline)
        assertNull(GoalFeedback.summarize(records,goals,2,at).period)
        val more=records+body("2026-10-18",70.5)
        val monday=GoalFeedback.summarize(more,goals,7,date("2026-10-19"))
        assertNotNull(monday.period)
        assertFalse(monday.period!!.end.isAfter(date("2026-10-19").day()))
        assertEquals(week.period.change,GoalFeedback.summarize(records+body("2026-10-15",100.0),goals,7,at).period!!.change,0.0)
    }
    @Test fun referenceProgressHandlesLossMissingDaysAndInvalidGoals() {
        val goals=defaultProfile().put("fitnessGoal","减脂").put("baselineWeight",80).put("targetWeight",70).put("weeklyWeightTarget",-.5)
        val records=listOf(body("2026-10-12",80.0),body("2026-10-14",79.6))
        val period=GoalFeedback.summarize(records,goals,7,at).period!!
        assertTrue(period.change<0 && period.targetChange<0 && period.fraction>0 && period.fraction<1)
        assertNull(GoalFeedback.summarize(records.take(1),goals,7,at).period)
        assertNull(GoalFeedback.summarize(records,goals.copy().put("weeklyWeightTarget",0),7,at).period)
        assertNull(GoalFeedback.summarize(records,goals.copy().put("fitnessGoal","维持"),7,at).period)
        assertNull(GoalFeedback.summarize(records,goals,30,date("2026-10-23")).period)
    }
    @Test fun staleMeasurementsInvalidDirectionAndInvalidGoalsHaveSpecificFeedback() {
        val records=listOf(body("2026-10-13",70.0))
        val invalid=defaultProfile().put("fitnessGoal","减脂").put("baselineWeight",70).put("targetWeight",75).put("weeklyWeightTarget",.5)
        assertEquals("请先核对身体目标",GoalFeedback.summarize(records,invalid,7,at).headline)
        assertEquals("最近测量已超过 7 天",GoalFeedback.summarize(records,defaultProfile(),7,date("2026-10-23")).headline)
        assertTrue(GoalFeedback.summarize(records,defaultProfile().put("proteinGoal",0),7,at).actions.first().contains("蛋白质目标"))
    }
    @Test fun completedTrainingExcludesOngoingAndFutureFinish() {
        val complete=Record.create(RecordType.WORKOUT,date("2026-10-14",12)).apply { json.put("endDate",date("2026-10-14",13)) }
        val future=complete.copy().apply { json.put("id","future").put("endDate",date("2026-10-15")) }
        val active=Record.create(RecordType.WORKOUT,date("2026-10-14",12))
        assertEquals(1,GoalFeedback.summarize(listOf(complete,future,active),defaultProfile(),7,at).completedWorkouts)
    }
}
