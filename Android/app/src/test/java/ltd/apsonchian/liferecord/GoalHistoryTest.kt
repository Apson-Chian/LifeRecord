package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import org.json.*
import org.junit.Test
import org.junit.Assert.*
import java.time.*

class GoalHistoryTest {
    private val day=LocalDate.of(2026,10,22)
    private fun stamp(d:LocalDate)=d.epochAt(LocalTime.NOON)
    @Test fun firstChangeFreezesOldRingsAndOnlyChangesTheEffectiveDayAndLater() {
        val original=defaultProfile()
        val changed=GoalHistory.changed(original,original.copy().put("proteinGoal",150.0).put("carbsGoal",300.0),stamp(day),day)
        assertEquals(100.0,GoalHistory.at(changed,day.minusDays(1)).getDouble("proteinGoal"),0.0)
        assertEquals(150.0,GoalHistory.at(changed,day).getDouble("proteinGoal"),0.0)
        assertEquals(150.0,GoalHistory.at(changed,day.plusYears(1)).getDouble("proteinGoal"),0.0)
        assertEquals(1.0,100/GoalHistory.at(changed,day.minusDays(1)).getDouble("proteinGoal"),0.0)
        assertEquals(2,GoalHistory.versions(changed).size)
        assertNull(GoalHistory.weightStageStart(changed,day))
        val bodyChange=GoalHistory.changed(changed,changed.copy().put("targetWeight",65.0),stamp(day)+10,day)
        assertEquals(day,GoalHistory.weightStageStart(bodyChange,day))
        assertFalse(original.has("goalHistory"))
        Validation.historicalProfile(changed)
        java.io.File("build/outputs/tests/goal-history.json").apply {parentFile?.mkdirs();writeText(changed.toString(2))}
    }
    @Test fun sameDayChangesReplaceOnlyThatDayAndNoOpEditsDoNotCreateVersions() {
        val first=GoalHistory.changed(defaultProfile(),defaultProfile().put("proteinGoal",150.0),stamp(day),day)
        val second=GoalHistory.changed(first,first.copy().put("proteinGoal",160.0),stamp(day),day)
        assertEquals(160.0,GoalHistory.at(second,day).getDouble("proteinGoal"),0.0)
        assertEquals(2,GoalHistory.versions(second).size)
        val renamed=GoalHistory.changed(second,second.copy().put("displayName","新称呼"),stamp(day),day)
        assertEquals(2,GoalHistory.versions(renamed).size)
        val tomorrow=GoalHistory.changed(second,second.copy().put("proteinGoal",180.0),stamp(day.plusDays(1)),day.plusDays(1))
        assertEquals(160.0,GoalHistory.at(tomorrow,day).getDouble("proteinGoal"),0.0)
        assertEquals(180.0,GoalHistory.at(tomorrow,day.plusDays(1)).getDouble("proteinGoal"),0.0)
    }
    @Test fun offlineChangesMergeTheirDatesEvenWhenTheOuterProfileLoses() {
        val base=defaultProfile()
        val early=GoalHistory.changed(base,base.copy().put("proteinGoal",120.0),stamp(day.minusDays(2)),day.minusDays(2))
        val late=GoalHistory.changed(base,base.copy().put("proteinGoal",150.0),stamp(day),day)
        val merged=GoalHistory.mergedProfile(late,early)
        assertEquals(150.0,merged.getDouble("proteinGoal"),0.0)
        assertEquals(120.0,GoalHistory.at(merged,day.minusDays(1)).getDouble("proteinGoal"),0.0)
        assertEquals(100.0,GoalHistory.at(merged,day.minusDays(3)).getDouble("proteinGoal"),0.0)
        assertEquals(GoalHistory.merge(early,late).toString(),GoalHistory.merge(late,early).toString())
    }
    @Test fun feedbackCountsEachDaysOwnTargetInsteadOfTodaysTarget() {
        val profile=GoalHistory.changed(defaultProfile(),defaultProfile().put("calorieGoal",2400.0).put("proteinGoal",150.0),stamp(day),day)
        val meals=listOf(day.minusDays(1),day).map {d ->Record.create(RecordType.MEAL,d.epochAt(LocalTime.MIN)).apply {json.put("name","当天餐食").put("calories",2000.0).put("protein",100.0)}}
        val summary=GoalFeedback.summarize(meals,profile,7,stamp(day))
        assertEquals(2,summary.mealDays);assertEquals(1,summary.calorieDays);assertEquals(1,summary.proteinDays)
    }
    @Test fun coachGoalWritesUseTheSameHistoricalVersionPath() {
        val original=Snapshot(emptyList(),defaultProfile(),emptyList())
        val changed=ltd.apsonchian.liferecord.service.AgentActions.apply(original,listOf(JSONObject().put("type","update_goals").put("proteinGoal",150.0)),"更新蛋白质目标","fixture")
        assertEquals(100.0,GoalHistory.at(changed.profile,LocalDate.now().minusDays(1)).getDouble("proteinGoal"),0.0)
        assertEquals(150.0,GoalHistory.at(changed.profile,LocalDate.now()).getDouble("proteinGoal"),0.0)
        assertFalse(original.profile.has("goalHistory"))
    }
}
