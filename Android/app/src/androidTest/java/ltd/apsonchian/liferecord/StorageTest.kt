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
    @Test fun privateCameraUriAcceptsPhotoAndDoesNotExposeMealOrDatabaseDirectories() {
        val app=ApplicationProvider.getApplicationContext<LifeRecordApplication>()
        val uri=app.photos.captureUri()
        try {
            assertEquals("${app.packageName}.camera",uri.authority)
            val bitmap=android.graphics.Bitmap.createBitmap(8,12,android.graphics.Bitmap.Config.ARGB_8888)
            app.contentResolver.openOutputStream(uri)!!.use {bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG,90,it)};bitmap.recycle()
            assertTrue(app.photos.read(uri).isNotEmpty())
            val avatar=app.photos.readAvatar(uri);assertTrue(avatar.size<=512_000)
            val decoded=android.graphics.BitmapFactory.decodeByteArray(avatar,0,avatar.size)
            assertEquals(512,decoded.width);assertEquals(512,decoded.height);decoded.recycle()
            assertThrows(IllegalArgumentException::class.java) {androidx.core.content.FileProvider.getUriForFile(app,"${app.packageName}.camera",java.io.File(app.filesDir,"meal-photos/private.jpg"))}
        } finally {app.photos.discardCapture(uri)}
        assertThrows(java.io.FileNotFoundException::class.java) {app.contentResolver.openInputStream(uri)}
    }
    @Test fun oldJsonStoreMigratesToTypedFieldsWithoutLosingNestedData() {
        val app=ApplicationProvider.getApplicationContext<LifeRecordApplication>()
        val name="migration-${java.util.UUID.randomUUID()}.db"
        val record=Record.create(RecordType.WORKOUT).apply { json.put("bodyParts",JSONArray().put("背部"));json.put("exercises",JSONArray().put(JSONObject().put("name","划船").put("sets",JSONArray().put(JSONObject().put("weight",40).put("reps",8).put("durationSeconds",JSONObject.NULL))))) }
        try {
            app.openOrCreateDatabase(name,android.content.Context.MODE_PRIVATE,null).use { db ->
                db.execSQL("CREATE TABLE records(type TEXT,id TEXT,payload TEXT,PRIMARY KEY(type,id))")
                db.execSQL("CREATE TABLE values_store(name TEXT PRIMARY KEY,payload TEXT)")
                db.execSQL("INSERT INTO records VALUES(?,?,?)",arrayOf(record.type.name,record.id,record.json.toString()))
                db.execSQL("INSERT INTO values_store VALUES(?,?)",arrayOf("profile",defaultProfile().toString()))
                db.version=1
            }
            Store(app,name).use { store ->
                val saved=store.load().records.single()
                assertEquals(record.id,saved.id)
                assertEquals(40.0,saved.json.getJSONArray("exercises").getJSONObject(0).getJSONArray("sets").getJSONObject(0).getDouble("weight"),0.0)
                assertTrue(saved.json.getJSONArray("exercises").getJSONObject(0).getJSONArray("sets").getJSONObject(0).isNull("durationSeconds"))
                store.readableDatabase.rawQuery("PRAGMA table_info(records)",null).use { c -> while(c.moveToNext()) assertNotEquals("payload",c.getString(1)) }
                store.set("test.chat","[{\"role\":\"user\",\"content\":\"hello\"}]")
                assertEquals("hello",JSONArray(store.get("test.chat")).getJSONObject(0).getString("content"))
                store.clearAll();assertTrue(store.load().records.isEmpty());assertEquals("",store.get("test.chat"))
            }
        } finally { app.deleteDatabase(name) }
    }
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
        try { val reopened=Secrets(app);assertEquals("test-a",reopened.get("test.deepseek"));assertEquals("test-b",reopened.get("test.glm"));reopened.clear();assertEquals("",reopened.get("test.deepseek"));assertEquals("",reopened.get("test.glm")) } finally { app.secrets.save("test.deepseek","");app.secrets.save("test.glm","") }
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
