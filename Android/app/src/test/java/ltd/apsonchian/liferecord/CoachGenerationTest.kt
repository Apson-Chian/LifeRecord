package ltd.apsonchian.liferecord

import ltd.apsonchian.liferecord.data.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CoachGenerationTest {
    private fun chat(vararg messages:JSONObject)=listOf(JSONObject().put("id","chat").put("messages",JSONArray(messages.toList())))
    @Test fun interruptedRequestPreservesOriginalQuestionPhotosAndTime() {
        val q=CoachGeneration.question("午餐照片","",listOf("photo.jpg"),123.0)
        val restored=CoachGeneration.recover(chat(q)).single().getJSONArray("messages").getJSONObject(0)
        assertEquals("failed",restored.getString("generationState"));assertEquals(q.getString("id"),restored.getString("id"))
        assertEquals(123.0,restored.getDouble("createdAt"),0.0);assertEquals("photo.jpg",restored.getJSONArray("localPhotoFiles").getString(0))
        assertEquals(restored.getString("id"),CoachGeneration.retryable(listOf(restored))?.getString("id"))
    }
    @Test fun interruptedWriterMustNotBeAutomaticallyReplayed() {
        val q=CoachGeneration.question("帮我记录午餐","",emptyList(),123.0).put("generationState","applying")
        val restored=CoachGeneration.recover(chat(q)).single().getJSONArray("messages").getJSONObject(0)
        assertEquals("needsReview",restored.getString("generationState"));assertNull(CoachGeneration.retryable(listOf(restored)))
    }
    @Test fun retryUpdatesOriginalMessageWithoutDuplicatingIt() {
        val q=CoachGeneration.question("问题","问题",emptyList(),123.0)
        val updated=CoachGeneration.update(chat(q),"chat",q.getString("id"),"failed","offline")
        val retried=CoachGeneration.update(updated,"chat",q.getString("id"),"pending")
        val messages=retried.single().getJSONArray("messages").objects()
        assertEquals(1,messages.size);assertEquals(q.getString("id"),messages.single().getString("id"))
        assertEquals(123.0,messages.single().getDouble("createdAt"),0.0)
    }
    @Test fun retryHistoryStopsAtOriginalQuestionAndExcludesFailureText() {
        val first=CoachGeneration.question("第一问","",emptyList(),123.0)
        val second=CoachGeneration.question("第二问","",emptyList(),124.0)
        val failure=JSONObject().put("role","assistant").put("content","回答失败：offline")
        val history=CoachGeneration.history(listOf(first,failure,second),first.getString("id"))
        assertEquals(1,history.size);assertEquals("第一问",history.single().getString("content"))
        assertEquals(2,CoachGeneration.history(listOf(first,failure,second),second.getString("id")).size)
    }
    @Test fun onlyLatestFailedQuestionCanRetryAndStoppedMessagesStayStopped() {
        val failed=CoachGeneration.question("第一问","",emptyList(),123.0).put("generationState","failed")
        val next=CoachGeneration.question("第二问","",emptyList(),124.0).put("generationState","stopped")
        assertNull(CoachGeneration.retryable(listOf(failed,next)))
        val restored=CoachGeneration.recover(chat(next)).single().getJSONArray("messages").getJSONObject(0)
        assertEquals("stopped",restored.getString("generationState"))
    }
    @Test fun deletedConversationCannotBeResurrectedByLateCompletion() {
        assertTrue(CoachGeneration.update(emptyList(),"chat","gone","failed").isEmpty())
    }
}
