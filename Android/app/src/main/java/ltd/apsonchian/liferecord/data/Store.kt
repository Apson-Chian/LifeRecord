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

/** Version 2 stores typed relational fields, including nested workout sets and chats. */
class Store(context: Context, databaseName: String = "liferecord.db") : SQLiteOpenHelper(context, databaseName, null, 2) {
    override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE records(type TEXT NOT NULL, id TEXT NOT NULL, PRIMARY KEY(type,id))")
        db.execSQL("CREATE TABLE documents(name TEXT PRIMARY KEY)")
        db.execSQL("CREATE TABLE fields(document TEXT NOT NULL REFERENCES documents(name) ON DELETE CASCADE,node INTEGER NOT NULL,parent INTEGER,name TEXT NOT NULL,kind TEXT NOT NULL,text_value TEXT,number_value REAL,PRIMARY KEY(document,node))")
    }
    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) {
        if(old < 2) {
            db.execSQL("ALTER TABLE records RENAME TO legacy_records")
            db.execSQL("ALTER TABLE values_store RENAME TO legacy_values")
            onCreate(db)
            db.rawQuery("SELECT type,id,payload FROM legacy_records",null).use { c -> while(c.moveToNext()) {
                val type=c.getString(0);val id=c.getString(1)
                db.insertOrThrow("records",null,ContentValues().apply {put("type",type);put("id",id)})
                writeDocument(db,"record:$type:$id",JSONObject(c.getString(2)))
            } }
            db.rawQuery("SELECT name,payload FROM legacy_values",null).use { c -> while(c.moveToNext()) { writeDocument(db,c.getString(0),parseValue(c.getString(1))) } }
            db.execSQL("DROP TABLE legacy_records");db.execSQL("DROP TABLE legacy_values")
        }
    }
    private fun parseValue(value: String): Any = if(value.trimStart().startsWith("{")) JSONObject(value) else if(value.trimStart().startsWith("[")) org.json.JSONArray(value) else value
    private fun writeDocument(db:SQLiteDatabase,document:String,value:Any?) {
        db.insertWithOnConflict("documents",null,ContentValues().apply {put("name",document)},SQLiteDatabase.CONFLICT_IGNORE)
        db.delete("fields","document=?",arrayOf(document))
        var index=0
        fun add(child:Any?,parent:Int?,name:String,depth:Int) {
            require(depth<=16 && index<100000) { "存储内容过于复杂" }
            val node=index++
            val kind=when(child) { null,JSONObject.NULL -> "null";is JSONObject -> "object";is org.json.JSONArray -> "array";is Boolean -> "bool";is Number -> "number";else -> "text" }
            db.insertOrThrow("fields",null,ContentValues().apply {
                put("document",document);put("node",node);if(parent==null) putNull("parent") else put("parent",parent);put("name",name);put("kind",kind)
                if(kind=="text") put("text_value",child.toString())
                if(kind=="number") put("number_value",(child as Number).toDouble())
                if(kind=="bool") put("number_value",if(child==true) 1 else 0)
            })
            if(child is JSONObject) child.keys().forEach { add(child.get(it),node,it,depth+1) }
            if(child is org.json.JSONArray) for(i in 0 until child.length()) add(child.get(i),node,i.toString(),depth+1)
        }
        add(value,null,"",0)
    }
    private fun readDocument(db:SQLiteDatabase,document:String):Any? {
        val values=mutableMapOf<Int,Any>()
        db.rawQuery("SELECT node,parent,name,kind,text_value,number_value FROM fields WHERE document=? ORDER BY node",arrayOf(document)).use { c -> while(c.moveToNext()) {
            val value:Any=when(c.getString(3)) { "null" -> JSONObject.NULL;"object" -> JSONObject();"array" -> org.json.JSONArray();"bool" -> c.getInt(5)!=0;"number" -> c.getDouble(5);else -> c.getString(4) }
            values[c.getInt(0)]=value
            if(!c.isNull(1)) when(val parent=values[c.getInt(1)]) {is JSONObject -> parent.put(c.getString(2),value);is org.json.JSONArray -> parent.put(value)}
        } }
        return values[0]
    }
    @Synchronized fun clearAll() {
        val db=writableDatabase;db.beginTransaction()
        try { db.delete("records",null,null);db.delete("documents",null,null);db.setTransactionSuccessful() } finally {db.endTransaction()}
    }
    @Synchronized fun load(): Snapshot {
        val db=readableDatabase; val records=mutableListOf<Record>()
        db.rawQuery("SELECT type,id FROM records",null).use { c -> while(c.moveToNext()) {
            val type=c.getString(0); val id=c.getString(1)
            records+=Record(RecordType.valueOf(type),readDocument(db,"record:$type:$id") as JSONObject)
        } }
        return Snapshot(records,JSONObject(get("profile",defaultProfile().toString())),org.json.JSONArray(get("deletions","[]")).objects())
    }
    @Synchronized fun commit(s:Snapshot, values:Map<String,String> = emptyMap()) {
        val db=writableDatabase;db.beginTransaction()
        try {
            db.delete("records",null,null)
            db.delete("documents","name LIKE ?",arrayOf("record:%"))
            s.records.forEach { r ->
                db.insertOrThrow("records",null,ContentValues().apply {put("type",r.type.name);put("id",r.id)})
                writeDocument(db,"record:${r.type.name}:${r.id}",r.json)
            }
            writeDocument(db,"profile",s.profile);writeDocument(db,"deletions",org.json.JSONArray(s.deletions))
            values.forEach {(key,value)->writeDocument(db,key,parseValue(value))}
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    @Synchronized fun get(key:String,fallback:String=""):String = readDocument(readableDatabase,key)?.toString() ?: fallback
    @Synchronized fun set(key:String,value:String) {
        val db=writableDatabase;db.beginTransaction()
        try {writeDocument(db,key,parseValue(value));db.setTransactionSuccessful()} finally {db.endTransaction()}
    }
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
    fun clear() { check(preferences.edit().clear().commit()) { "密钥清除失败" } }
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
