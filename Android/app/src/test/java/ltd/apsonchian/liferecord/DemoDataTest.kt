package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime

class DemoDataTest {
    private val at = LocalDate.of(2026,10,20).epochAt(LocalTime.of(0,5))
    @Test fun completeExamplesHaveValidDatesNutritionAndWorkoutDetails() {
        val records = DemoData.records(at)
        val meals = records.filter {it.type==RecordType.MEAL}
        val body = records.filter {it.type==RecordType.BODY}
        val workouts = records.filter {it.type==RecordType.WORKOUT}
        assertEquals(106,meals.size); assertEquals(28,body.size); assertEquals(20,workouts.size)
        assertEquals(4,meals.map {it.json.getString("kind")}.distinct().size)
        assertTrue(records.all {it.demo && it.date<=at}); records.forEach(Validation::record)
        meals.forEach {r -> val j=r.json; assertEquals(j.getDouble("protein")*4+j.getDouble("carbs")*4+j.getDouble("fat")*9,j.getDouble("calories"),.001)}
        assertTrue(body.any {it.json.has("waist")});assertTrue(body.any {!it.json.has("bodyFat")})
        assertTrue(workouts.all {it.json.getDouble("endDate")<=at && it.json.getDouble("endDate")>it.date && it.json.getJSONArray("exercises").length()>0})
        assertTrue(workouts.any {it.json.getJSONArray("exercises").getJSONObject(0).getJSONArray("sets").getJSONObject(0).has("weight")})
        assertTrue(workouts.any {it.json.getJSONArray("exercises").getJSONObject(0).getJSONArray("sets").getJSONObject(0).has("durationSeconds")})
    }
    @Test fun examplesNeverEnterSyncQualityOrRealTrends() {
        val records=DemoData.records(at)
        val snapshot=Snapshot(records,defaultProfile(),emptyList())
        val wire=Merge.wire(snapshot)
        listOf("meals","bodyMetrics","workoutEntries").forEach {assertEquals(0,wire.getJSONArray(it).length())}
        assertTrue(RecordQuality.issues(records,at).isEmpty())
        assertTrue(BodyTrend.records(records,"weight",at).isEmpty())
        assertEquals(28,BodyTrend.records(records,"weight",at,includeDemo=true).size)
        assertTrue(BodyOverview.summarize(records,at).points.isEmpty())
        assertEquals(28,BodyOverview.summarize(records,at,includeDemo=true).points.size)
        assertEquals(0,Insights.streak(records,at.day()))
        val chats=DemoData.conversations(at)
        assertEquals(2,chats.size);assertTrue(chats.all {it.getBoolean("isDemo")})
        assertTrue(CoachGeneration.recover(chats).all {chat -> chat.getJSONArray("messages").objects().none {it.optString("generationState")=="failed"}})
    }
}
