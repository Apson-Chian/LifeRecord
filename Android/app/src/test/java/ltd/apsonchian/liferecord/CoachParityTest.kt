package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.*
import org.json.*
import org.junit.Assert.*
import org.junit.Test
import java.time.*

class CoachParityTest {
    @Test fun identityRejectsEmptyOverlongAndControlNames() {
        assertEquals("力量教练",CoachIdentity.validated(" 力量教练 ",null).name)
        listOf(" ","a".repeat(31),"教练\n名字","名字\t").forEach {name ->
            // A trailing whitespace is trimmed, internal control characters are rejected.
            if(name=="名字\t") assertEquals("名字",CoachIdentity.validated(name,null).name)
            else assertThrows(IllegalArgumentException::class.java) {CoachIdentity.validated(name,null)}
        }
        assertThrows(IllegalArgumentException::class.java) {CoachIdentity.validated("教练",ByteArray(512_001))}
    }
    @Test fun readOnlyRequestsCannotMasqueradeAsSavedRecords() {
        val empty=JSONObject().put("answer","已保存").put("actions",JSONArray())
        assertTrue(CoachPolicy.blocked(empty,false,"帮我添加到餐食")!!.startsWith("未保存"))
        assertNull(CoachPolicy.blocked(empty,false,"今天适合加餐吗"))
        empty.put("actions",JSONArray().put(JSONObject().put("type","add_meal")))
        assertNotNull(CoachPolicy.blocked(empty,false,"请分析图片"))
        assertNull(CoachPolicy.blocked(empty,true,"帮我记录"))
    }
    @Test fun mealUsesCurrentTimeWhenUnspecifiedAndKeepsEstimateProvenance() {
        val action=JSONObject().put("type","add_meal").put("name","鸡胸饭").put("calories",600).put("protein",42).put("note","按常见一份估算")
        val before=now()
        val result=AgentActions.apply(Snapshot(emptyList(),defaultProfile(),emptyList()),listOf(action),"帮我添加到餐食","conversation").records.single()
        assertTrue(result.date in before..now());assertEquals(600.0,result.json.getDouble("calories"),0.0)
        assertEquals("AI 估算",result.json.getString("source"));assertEquals("conversation",result.json.getString("sourceConversationID"))
        assertEquals("帮我添加到餐食",result.json.getString("inputText"))
        action.remove("calories")
        assertThrows(IllegalArgumentException::class.java) {AgentActions.apply(Snapshot(emptyList(),defaultProfile(),emptyList()),listOf(action),"","c")}
        assertThrows(IllegalArgumentException::class.java) {AgentActions.apply(Snapshot(emptyList(),defaultProfile(),emptyList()),listOf(JSONObject().put("type","add_weight")),"","c")}
    }
    @Test fun cancellationHookCancelsActualOkHttpCallBeforeItCanWriteOrConnect() {
        var canceled=false
        assertThrows(java.io.IOException::class.java) {
            Network().complete(providerConfig("自定义").put("model","test"),"local-test-key","test",emptyList(),onCall={it.cancel();canceled=it.isCanceled()})
        }
        assertTrue(canceled)
    }
}
