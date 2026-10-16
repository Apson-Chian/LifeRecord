package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import org.json.*
import org.junit.Assert.*
import org.junit.Test

class WorkoutPartsTest {
    private fun workout(part:String="手臂")=Record.create(RecordType.WORKOUT,1000.0).apply {
        json.put("endDate",2000.0);json.put("note","二头、三头");json.put("bodyParts",JSONArray().put(part))
        json.put("exercises",JSONArray().put(JSONObject().put("name","弯举").put("bodyPart",part).put("sets",JSONArray().put(JSONObject().put("weight",20).put("reps",8)))))
    }
    private fun snapshot(vararg records:Record)=Snapshot(records.toList(),defaultProfile(),emptyList())
    private fun reply(vararg changes:Pair<String,List<String>>)=JSONObject().put("answer","请核对").put("changes",JSONArray(changes.map {(id,values)->JSONObject().put("id",id).put("bodyParts",JSONArray(values))}))
    @Test fun renameUpdatesAllHistoryNestedExercisesAndLibraryWithoutChangingSetsOrTime() {
        val record=workout();val template=Record.create(RecordType.EXERCISE).apply {json.put("name","弯举");json.put("bodyPart","手臂")}
        val (result,catalog)=WorkoutParts.rename(snapshot(record,template),parts+"手臂","手臂","上肢")
        assertTrue("上肢" in catalog);assertFalse("手臂" in catalog)
        val saved=result.records.first();assertEquals(listOf("上肢"),WorkoutParts.of(saved));assertEquals(1000.0,saved.date,0.0);assertEquals(2000.0,saved.json.getDouble("endDate"),0.0)
        assertEquals("二头、三头",saved.json.getString("note"));val exercise=saved.json.getJSONArray("exercises").getJSONObject(0)
        assertEquals("上肢",exercise.getString("bodyPart"));assertEquals(20,exercise.getJSONArray("sets").getJSONObject(0).getInt("weight"))
        assertEquals("上肢",result.records.last().json.getString("bodyPart"));assertEquals(listOf("手臂"),WorkoutParts.of(record))
        assertThrows(IllegalArgumentException::class.java) {WorkoutParts.rename(snapshot(record),parts+"手臂","手臂","胸部")}
    }
    @Test fun armRepairNeverInfersFromNegationPlansQuestionsOrHistoricalDescriptions() {
        assertEquals(listOf("二头","三头"),WorkoutParts.refineArms(listOf("手臂"),"二头、三头"))
        listOf("没练二头，只练三头","下次练二头","之前练过小臂","是否练三头？","可能练二头","二头休息").forEach {assertEquals(listOf("手臂"),WorkoutParts.refineArms(listOf("手臂"),it))}
        assertEquals(listOf("胸部","二头","三头","小臂","背部"),WorkoutParts.splitArms(listOf("胸部","手臂","背部")))
    }
    @Test fun reviewRejectsUnknownDuplicateOutOfFocusInvalidAndExcessiveChanges() {
        val r=workout()
        assertThrows(IllegalStateException::class.java) {WorkoutParts.review(reply("missing" to listOf("背部")),listOf(r))}
        assertThrows(IllegalArgumentException::class.java) {WorkoutParts.review(reply(r.id to listOf("背部"),r.id.uppercase() to listOf("胸部")),listOf(r))}
        assertThrows(IllegalArgumentException::class.java) {WorkoutParts.review(reply(r.id to listOf("背部")),listOf(r),"胸部")}
        listOf(listOf("未分类"),listOf("背部","背部"),listOf("背部\n胸部")).forEach {assertThrows(IllegalArgumentException::class.java) {WorkoutParts.review(reply(r.id to it),listOf(r))}}
        assertTrue(WorkoutParts.review(reply(r.id to listOf("手臂")),listOf(r)).changes.isEmpty())
    }
    @Test fun previewApplyIsAtomicOnStaleDeletedAndOutOfScopeRecords() {
        val a=workout();val b=workout();val source=snapshot(a,b)
        val plan=WorkoutParts.review(reply(a.id to listOf("二头"),b.id to listOf("三头")),source.records)
        val changed=b.copy().apply {json.put("note","已编辑")}
        assertThrows(IllegalArgumentException::class.java) {WorkoutParts.apply(snapshot(a,changed),plan,setOf(a.id,b.id))}
        assertThrows(IllegalStateException::class.java) {WorkoutParts.apply(snapshot(a),plan,setOf(a.id,b.id))}
        assertThrows(IllegalArgumentException::class.java) {WorkoutParts.apply(source,plan,setOf(a.id))}
        assertEquals(listOf("手臂"),WorkoutParts.of(a))
        val unrelated=Record.create(RecordType.BODY).apply {json.put("weight",72)}
        val result=WorkoutParts.apply(snapshot(a,b,unrelated),plan,setOf(a.id,b.id))
        assertEquals(listOf("二头"),WorkoutParts.of(result.records.first()));assertEquals(unrelated.json.toString(),result.records.last().json.toString())
    }
    @Test fun classificationRequiresExactlyAllInputIDsAndOnlyAvailableParts() {
        val r=workout("").apply {json.put("bodyParts",JSONArray())}
        fun classified(id:String=r.id,values:List<String> = listOf("二头"))=JSONObject().put("suggestions",JSONArray().put(JSONObject().put("id",id).put("bodyParts",JSONArray(values))))
        assertEquals(listOf("二头"),WorkoutParts.classification(classified(),listOf(r),parts).changes.single().bodyParts)
        assertThrows(IllegalArgumentException::class.java) {WorkoutParts.classification(classified("missing"),listOf(r),parts)}
        assertThrows(IllegalArgumentException::class.java) {WorkoutParts.classification(classified(values=listOf("已移除部位")),listOf(r),parts)}
        assertTrue(WorkoutParts.classification(classified(values=emptyList()),listOf(r),parts).changes.isEmpty())
    }
    @Test fun manualRepairCanAtomicallyHandleMoreThanThirtyHistoricalRecords() {
        val records=(1..35).map {workout()}
        val plan=PartPlan("手动复核",records.map {PartChange(it.id,listOf("二头","三头"))},records.map {it.copy()})
        val result=WorkoutParts.apply(Snapshot(records,defaultProfile(),emptyList()),plan,records.map {it.id}.toSet())
        assertEquals(35,result.records.count {WorkoutParts.of(it)==listOf("二头","三头")})
        assertTrue(records.all {WorkoutParts.of(it)==listOf("手臂")})
    }
}
