package ltd.apsonchian.liferecord.ui

import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.snapshots.SnapshotStateMap
import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.Photos
import org.json.JSONArray
import org.json.JSONObject

private fun encodeRecord(record: Record) = JSONObject().put("type", record.type.name).put("record", record.json).toString()
private fun decodeRecord(raw: String): Record = JSONObject(raw).let { Record(RecordType.valueOf(it.getString("type")), it.getJSONObject("record")) }
internal val RecordSaver = Saver<Record, String>(save = { encodeRecord(it) }, restore = ::decodeRecord)
internal val OptionalRecordSaver = Saver<Record?, String>(
    save = { it?.let(::encodeRecord).orEmpty() }, restore = { if (it.isEmpty()) null else decodeRecord(it) },
)
internal val FieldMapSaver = Saver<SnapshotStateMap<String, String>, String>(
    save = { JSONObject(it.toMap()).toString() },
    restore = { raw -> JSONObject(raw).let { json -> mutableStateMapOf<String, String>().apply { json.keys().forEach { put(it, json.getString(it)) } } } },
)
internal val ExerciseListSaver = Saver<List<JSONObject>, String>(save = { JSONArray(it).toString() }, restore = { JSONArray(it).objects() })
internal val SetRowsSaver = Saver<List<List<String>>, String>(
    save = { JSONArray(it.map { row -> JSONArray(row) }).toString() },
    restore = { raw -> JSONArray(raw).let { rows -> (0 until rows.length()).map { rows.getJSONArray(it).strings() } } },
)
internal val StringSetSaver = Saver<Set<String>, ArrayList<String>>(save = { ArrayList(it) }, restore = { it.toSet() })

/** Only small file names enter SavedState, never photo bytes. Files stay in private storage. */
internal fun draftPhotoSaver(photos: Photos, owner: String) = Saver<List<ByteArray>, ArrayList<String>>(
    save = { ArrayList(photos.stageDraft(owner, it)) },
    restore = { names -> names.mapNotNull { photos.readDraft(owner, it) } },
)
