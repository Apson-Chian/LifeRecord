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
    @Test fun chatPhotosPersistAcrossInstancesAndDeleteIndividually() {
        val app=ApplicationProvider.getApplicationContext<LifeRecordApplication>()
        val bytes=byteArrayOf(1,2,3,4)
        val name=app.photos.saveChat(bytes)
        try { assertArrayEquals(bytes,ltd.apsonchian.liferecord.service.Photos(app).chat(name)) }
        finally { app.photos.deleteChat(name) }
        assertThrows(java.io.FileNotFoundException::class.java) { app.photos.chat(name) }
    }
    @Test fun gallerySavePublishesCompleteJpegWithoutGalleryReadPermission() {
        org.junit.Assume.assumeTrue(android.os.Build.VERSION.SDK_INT>=29)
        val app=ApplicationProvider.getApplicationContext<LifeRecordApplication>()
        val bitmap=android.graphics.Bitmap.createBitmap(2,2,android.graphics.Bitmap.Config.ARGB_8888)
        val bytes=java.io.ByteArrayOutputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG,90,it);it.toByteArray() }
        bitmap.recycle()
        val uri=app.photos.saveToGallery(bytes)
        try {
            assertArrayEquals(bytes,app.contentResolver.openInputStream(uri)!!.use { it.readBytes() })
            app.contentResolver.query(uri,arrayOf(android.provider.MediaStore.Images.Media.IS_PENDING),null,null,null)!!.use { cursor ->
                assertTrue(cursor.moveToFirst());assertEquals(0,cursor.getInt(0))
            }
        } finally { app.contentResolver.delete(uri,null,null) }
    }

}
