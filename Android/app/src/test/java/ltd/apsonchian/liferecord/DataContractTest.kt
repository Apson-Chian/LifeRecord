package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import org.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class DataContractTest {
    private val fixture = JSONObject(File("../../Tests/Fixtures/data-contract.json").readText())
    private val snapshot get() = fixture.getJSONObject("snapshot")
    private fun validate(kind: String, value: JSONObject) {
        if (kind == "settings") Validation.profile(value)
        else Validation.record(Record(RecordType.values().single { it.wire == kind }, value))
    }
    @Test fun sharedSnapshotRoundTripsWithoutDroppingExtensionsOrNull() {
        val local = Snapshot(emptyList(), defaultProfile().put("updatedAt", 1), emptyList())
        val result = Merge.apply(local, snapshot)
        val wire = Merge.wire(result)
        assertEquals(78.0, wire.getJSONArray("bodyMetrics").getJSONObject(0).getDouble("bodyFat"), 0.0)
        assertTrue(wire.getJSONArray("bodyMetrics").getJSONObject(0).isNull("waist"))
        assertEquals("must survive", wire.getJSONArray("meals").getJSONObject(0).getJSONObject("extension").getString("origin"))
        assertEquals(12, wire.getJSONArray("meals").getJSONObject(0).getJSONArray("photoIDs").length())
        val target=File("build/outputs/tests/contract-android.json"); target.parentFile?.mkdirs(); target.writeText(wire.toString(2))
    }
    @Test fun sharedNumericBoundsAndTypes() {
        val limits=fixture.getJSONObject("limits")
        limits.keys().forEach { kind ->
            val original = if(kind=="settings") snapshot.getJSONObject("settings") else snapshot.getJSONArray(if(kind=="meal") "meals" else "bodyMetrics").getJSONObject(0)
            val fields=limits.getJSONObject(kind)
            fields.keys().forEach { field ->
                val bounds=fields.getJSONArray(field); val low=bounds.getDouble(0); val high=bounds.getDouble(1)
                listOf(low,high).forEach { value -> validate(kind,original.copy().put(field,value)) }
                listOf<Any>(low-1,high+1,true,low.toString(),JSONArray()).forEach { value ->
                    assertThrows("$kind.$field=$value", IllegalArgumentException::class.java) { validate(kind,original.copy().put(field,value)) }
                }
            }
        }
    }
    @Test fun historicalOutliersAndAbsentLegacyNutritionRemainReadable() {
        val raw=snapshot.copy()
        raw.put("meals",JSONArray().put(fixture.getJSONObject("legacyMeal")))
        raw.getJSONArray("bodyMetrics").getJSONObject(0).put("bodyFat",0)
        val result=Merge.apply(Snapshot(emptyList(),defaultProfile().put("updatedAt",1),emptyList()),raw)
        assertEquals(0.0,result.records.single {it.type==RecordType.BODY}.json.getDouble("bodyFat"),0.0)
        assertFalse(result.records.single {it.type==RecordType.MEAL}.json.has("fiber"))
        assertEquals(fixture.getJSONObject("legacyMeal").toString(),result.records.single {it.type==RecordType.MEAL}.json.toString())
    }
    @Test fun legacyPartsFallbackAndExplicitEmptyAreDifferent() {
        val r=Record(RecordType.WORKOUT,snapshot.getJSONArray("workoutEntries").getJSONObject(0).copy())
        assertEquals(fixture.getJSONArray("expectedWorkoutParts").strings(),WorkoutParts.of(r))
        r.json.put("bodyParts",JSONArray())
        assertTrue(WorkoutParts.of(r).isEmpty())
    }
}
