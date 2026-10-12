package ltd.apsonchian.liferecord

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import ltd.apsonchian.liferecord.data.*
import org.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StorageTest {
    @Test fun databaseReopenPreservesOriginalIdAndOptionalFields() {
        val app=ApplicationProvider.getApplicationContext<LifeRecordApplication>()
        val r=Record.create(RecordType.BODY).apply { json.put("weight",72.3);json.put("bodyFat",JSONObject.NULL);json.put("waist",81.0) }
        val before=app.store.load()
        try {
            app.store.commit(before.copy(records=before.records+r))
            val reopened=Store(app)
            val saved=reopened.load().records.single { it.id==r.id }
            assertEquals(72.3,saved.json.getDouble("weight"),0.0);assertTrue(saved.json.isNull("bodyFat"));assertEquals(81.0,saved.json.getDouble("waist"),0.0)
            reopened.close()
        } finally {app.store.commit(before)}
    }
    @Test fun secretsAreIsolatedByProviderAndPersistAcrossInstances() {
        val app=ApplicationProvider.getApplicationContext<LifeRecordApplication>()
        app.secrets.save("test.deepseek","test-a");app.secrets.save("test.glm","test-b")
        try { val reopened=Secrets(app);assertEquals("test-a",reopened.get("test.deepseek"));assertEquals("test-b",reopened.get("test.glm")) } finally { app.secrets.save("test.deepseek","");app.secrets.save("test.glm","") }
    }
}
