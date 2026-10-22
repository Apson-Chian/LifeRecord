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
        assertTrue(meals.size in 95..115); assertEquals(29,body.size); assertTrue(workouts.size in 19..23)
        assertTrue(meals.map {it.title}.distinct().size>=16)
        assertTrue(meals.all {it.json.getString("inputText").isNotBlank()})
        assertTrue(workouts.flatMap {it.json.getJSONArray("bodyParts").strings()}.distinct().size>=8)
        assertTrue(records.none {it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) && it.date.day()==at.day()})
        assertEquals(3,records.count {it.type==RecordType.FAVORITE});assertEquals(4,records.count {it.type==RecordType.EXERCISE})
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
        assertEquals(27,BodyTrend.records(records,"weight",at,includeDemo=true).size)
        assertTrue(BodyOverview.summarize(records,at).points.isEmpty())
        assertEquals(27,BodyOverview.summarize(records,at,includeDemo=true).points.size)
        assertEquals(0,Insights.streak(records,at.day()))
        val chats=DemoData.conversations(at)
        assertEquals(2,chats.size);assertTrue(chats.all {it.getBoolean("isDemo")})
        assertTrue(CoachGeneration.recover(chats).all {chat -> chat.getJSONArray("messages").objects().none {it.optString("generationState")=="failed"}})
    }
}
