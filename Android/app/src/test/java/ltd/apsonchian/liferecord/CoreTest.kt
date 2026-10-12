package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.AgentActions
import org.json.*
import org.junit.Assert.*
import org.junit.Test
import java.time.*

class CoreTest {
    private fun meal()=Record.create(RecordType.MEAL).apply { json.put("name","午餐");json.put("calories",600);json.put("protein",40);json.put("carbs",65);json.put("fat",20) }
    private fun snapshot(vararg records:Record)=Snapshot(records.toList(),defaultProfile(),emptyList())
    @Test fun remoteDeletionWinsButNewerLocalEditSurvives() {
        val r=meal();r.json.put("updatedAt",200.0)
        fun remote(stamp:Double)=JSONObject().put("deletions",JSONArray().put(JSONObject().put("recordType","meal").put("id",r.id.uppercase()).put("deletedAt",stamp)))
        assertEquals(1,Merge.apply(snapshot(r),remote(199.0)).records.size)
        assertEquals(0,Merge.apply(snapshot(r),remote(200.0)).records.size)
    }
    @Test fun oldRemoteCannotOverwriteEditOrResurrectDeletion() {
        val r=meal();r.json.put("updatedAt",200.0)
        val old=r.copy().apply { json.put("updatedAt",100.0);json.put("name","旧值") }
        val remote=JSONObject().put("meals",JSONArray().put(old.json))
        assertEquals("午餐",Merge.apply(snapshot(r),remote).records.single().title)
        val deleted=snapshot().copy(deletions=listOf(JSONObject().put("id",r.id).put("recordType","meal").put("deletedAt",300.0)))
        assertTrue(Merge.apply(deleted,remote).records.isEmpty())
    }
    @Test fun demoAndLocalPhotoPathsDoNotLeaveDevice() {
        val real=meal().apply { json.put("localPhotoFiles",JSONArray().put("private.jpg"));json.put("uploadedPhotoFiles",JSONArray().put("private.jpg")) }
        val demo=meal().apply { json.put("isDemo",true) }
        val wire=Merge.wire(snapshot(real,demo));assertEquals(1,wire.getJSONArray("meals").length())
        val row=wire.getJSONArray("meals").getJSONObject(0);assertFalse(row.has("localPhotoFiles"));assertFalse(row.has("uploadedPhotoFiles"))
    }
    @Test fun aiPartialEditPreservesPhotoAndOriginalTime() {
        val r=meal().apply { json.put("photoIDs",JSONArray().put("a".repeat(32)));json.put("inputText","原始描述") }
        val a=JSONObject().put("type","update_meal").put("recordID",r.id).put("protein",50)
        val result=AgentActions.apply(snapshot(r),listOf(a),"改蛋白质","chat").records.single()
        assertEquals(r.id,result.id);assertEquals(r.date,result.date,0.0);assertEquals(600.0,result.json.getDouble("calories"),0.0)
        assertEquals("原始描述",result.json.getString("inputText"));assertEquals("a".repeat(32),result.json.getJSONArray("photoIDs").getString(0))
        assertEquals(40.0,r.json.getDouble("protein"),0.0)
    }
    @Test fun aiBatchFailureDoesNotMutateOriginal() {
        val r=meal();val valid=JSONObject().put("type","update_meal").put("recordID",r.id).put("name","更新")
        val bad=JSONObject().put("type","delete_meal").put("recordID","missing")
        assertThrows(IllegalStateException::class.java) { AgentActions.apply(snapshot(r),listOf(valid,bad),"","chat") }
        assertEquals("午餐",r.title)
    }
    @Test fun workoutCanCrossMidnightWithoutLosingSets() {
        val start=LocalDate.of(2026,10,11).atTime(LocalTime.of(23,30));val end=start.plusHours(2)
        val zone=ZoneId.systemDefault()
        val r=Record.create(RecordType.WORKOUT,start.atZone(zone).toEpochSecond().toDouble()).apply {
            json.put("endDate",end.atZone(zone).toEpochSecond());json.put("bodyParts",JSONArray().put("二头").put("三头"))
            json.put("exercises",JSONArray().put(JSONObject().put("name","弯举").put("sets",JSONArray().put(JSONObject().put("reps",8).put("weight",20).put("durationSeconds",JSONObject.NULL)))))
        }
        Validation.record(r);assertEquals(LocalDate.of(2026,10,11),r.date.day());assertEquals(7200.0,r.json.getDouble("endDate")-r.date,0.0)
        r.json.put("endDate",r.date-1);assertThrows(IllegalArgumentException::class.java) { Validation.record(r) }
    }
    @Test fun streakExcludesDemoAndFutureAndMissingDaysAreNotZero() {
        val today=LocalDate.now();val yesterday=meal().apply { json.put("date",today.minusDays(1).epochAt()) };val before=meal().apply {json.put("date",today.minusDays(2).epochAt())}
        val demo=meal().apply {json.put("isDemo",true)};val future=meal().apply {json.put("date",today.plusDays(1).epochAt())}
        assertEquals(2,Insights.streak(listOf(yesterday,before,demo,future),today));assertTrue(Insights.daily(listOf(yesterday,before),today).isEmpty())
    }
    @Test fun bodyMedianUsesAllMeasurementsForDay() {
        val body=listOf(70.0,72.0,71.0).map { w -> Record.create(RecordType.BODY).apply { json.put("weight",w) } }
        assertEquals(71.0,Insights.weights(body).single().second,0.0)
    }
    @Test fun actualWireFixtureForBackendCompatibility() {
        val r=meal().apply { json.put("inputText","一份午餐");json.put("photoIDs",JSONArray().put("a".repeat(32))) }
        val body=Record.create(RecordType.BODY).apply {json.put("weight",72.3);json.put("bodyFat",JSONObject.NULL);json.put("waist",81.0)}
        val workout=Record.create(RecordType.WORKOUT).apply {
            json.put("endDate",date+3600);json.put("bodyParts",JSONArray().put("二头").put("三头"))
            json.put("exercises",JSONArray().put(JSONObject().put("name","弯举").put("bodyPart","二头").put("sets",JSONArray().put(JSONObject().put("reps",8).put("weight",20).put("durationSeconds",JSONObject.NULL)))))
        }
        val wire=Merge.wire(snapshot(r,body,workout))
        val target=java.io.File("build/outputs/tests/android-sync-snapshot.json");target.parentFile?.mkdirs();target.writeText(wire.toString(2))
        assertEquals(1,wire.getJSONArray("workoutEntries").length())
    }
    @Test fun aiCannotRecordTrainingPlanWithoutEndTime() {
        val a=JSONObject().put("type","add_workout").put("date",OffsetDateTime.now().toString()).put("bodyParts",JSONArray().put("胸部"))
        assertThrows(IllegalArgumentException::class.java) { AgentActions.apply(snapshot(),listOf(a),"计划","chat") }
    }
}
