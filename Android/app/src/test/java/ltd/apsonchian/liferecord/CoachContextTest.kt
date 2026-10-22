package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class CoachContextTest {
    @Test fun allRealDatesAndAllFiveCollectionsReachContextWithoutFileReferences() {
        val records=RecordType.entries.map {type -> Record.create(type,now()-86400*400).apply {
            json.put("name","很早的记录").put("localPhotoFiles",JSONArray().put("private-file.jpg"))
        }}
        val snapshot=Snapshot(records+DemoData.records(),defaultProfile(),emptyList())
        val context=CoachContext.build(snapshot)
        assertEquals("all_local_records",context.getString("scope"));assertFalse(context.getBoolean("recordsTruncated"))
        RecordType.entries.forEach {type ->
            val entry=context.getJSONArray(type.collection).getJSONObject(0)
            assertEquals(records.first {it.type==type}.id,entry.getString("id"))
            assertTrue(entry.getString("localDateTime").contains("T"));assertFalse(entry.has("localPhotoFiles"))
            assertEquals(1,context.getJSONObject("recordCounts").getInt(type.collection))
        }
        assertFalse(context.toString().contains("private-file.jpg"))
        assertEquals(records.size,snapshot.records.count {!it.demo})
    }
    @Test fun demoContextIsExplicitReadOnlyAndNeverLeaksIntoSyncOrPersonalGoals() {
        val profile=defaultProfile().put("proteinGoal",87)
        val demo=DemoData.records()
        val snapshot=Snapshot(demo,profile,emptyList())
        val context=CoachContext.build(snapshot,demoConversation=true)
        assertEquals("synthetic_examples",context.getString("scope"))
        assertTrue(context.getJSONArray("meals").length()>90)
        assertEquals(130.0,context.getJSONObject("settings").getDouble("proteinGoal"),0.0)
        assertEquals(87,profile.getInt("proteinGoal"))
        assertEquals(0,Merge.wire(snapshot).getJSONArray("meals").length())
        assertFalse(CoachContext.scope(snapshot).demo) // New conversations can record the first real meal.
        val real=Record.create(RecordType.MEAL)
        assertFalse(CoachContext.scope(snapshot.copy(records=demo+real)).demo)
        assertTrue(CoachContext.scope(snapshot.copy(records=demo+real),demoConversation=true).demo)
    }
}
