package ltd.apsonchian.liferecord.data

import android.content.Context
import android.content.ContentValues
import android.database.sqlite.SQLiteOpenHelper
import android.database.sqlite.SQLiteDatabase
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class Store(context: Context) : SQLiteOpenHelper(context, "liferecord.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE records(type TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(type,id))")
        db.execSQL("CREATE TABLE values_store(name TEXT PRIMARY KEY, payload TEXT NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) = Unit
    @Synchronized fun load(): Snapshot {
        val records = mutableListOf<Record>()
        readableDatabase.rawQuery("SELECT type,payload FROM records", null).use { c -> while(c.moveToNext()) records += Record(RecordType.valueOf(c.getString(0)), JSONObject(c.getString(1))) }
        val deletions = org.json.JSONArray(get("deletions", "[]")).objects()
        return Snapshot(records, JSONObject(get("profile", defaultProfile().toString())), deletions)
    }
    @Synchronized fun commit(s: Snapshot) {
        val db = writableDatabase; db.beginTransaction()
        try {
            db.delete("records", null, null)
            s.records.forEach { r -> db.insertOrThrow("records", null, ContentValues().apply { put("type", r.type.name); put("id", r.id); put("payload", r.json.toString()) }) }
            set("profile", s.profile.toString()); set("deletions", org.json.JSONArray(s.deletions).toString())
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    @Synchronized fun get(key: String, fallback: String = ""): String = readableDatabase.rawQuery("SELECT payload FROM values_store WHERE name=?", arrayOf(key)).use { if(it.moveToFirst()) it.getString(0) else fallback }
    @Synchronized fun set(key: String, value: String) { writableDatabase.insertWithOnConflict("values_store", null, ContentValues().apply { put("name", key); put("payload", value) }, SQLiteDatabase.CONFLICT_REPLACE) }
}
/** Secrets are encrypted with a non-exportable Android Keystore AES key. Backup is disabled. */
class Secrets(context: Context) {
    private val preferences = context.getSharedPreferences("secrets", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (store.getKey("liferecord.secrets", null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("liferecord.secrets", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun save(name: String, value: String) {
        if(value.isBlank()) { preferences.edit().remove(name).commit(); return }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val bytes = cipher.doFinal(value.toByteArray())
        check(preferences.edit().putString(name, Base64.encodeToString(cipher.iv + bytes, Base64.NO_WRAP)).commit()) { "密钥保存失败" }
    }
    fun get(name: String): String {
        val raw = preferences.getString(name, null) ?: return ""
        val bytes = Base64.decode(raw, Base64.NO_WRAP)
        return Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0,12))) }.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
    }
}
