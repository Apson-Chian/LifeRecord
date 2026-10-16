package ltd.apsonchian.liferecord.data

import org.json.JSONArray
import org.json.JSONObject

data class PartChange(val id: String, val bodyParts: List<String>)
data class PartPlan(val answer: String, val changes: List<PartChange>, val originals: List<Record>)

object WorkoutParts {
    private fun canonical(value:Any?):String=when(value) {
        null,JSONObject.NULL -> "null"
        is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(",","{","}") {JSONObject.quote(it)+":"+canonical(value.get(it))}
        is JSONArray -> (0 until value.length()).joinToString(",","[","]") {canonical(value.get(it))}
        is Number -> value.toDouble().toString()
        is Boolean -> value.toString()
        else -> JSONObject.quote(value.toString())
    }
    val arms=listOf("二头","三头","小臂")
    fun valid(value: String)=value.isNotBlank() && value==value.trim() && value!="未分类" && value.codePointCount(0,value.length)<=30 && value.none {Character.isISOControl(it)}
    fun of(record: Record)=record.json.optJSONArray("bodyParts")?.strings().orEmpty()
    fun normalized(values: List<String>, catalog: List<String> = parts): List<String> {
        val clean=values.filter(::valid).distinct()
        return catalog.filter {it in clean} + clean.filter {it !in catalog}
    }
    fun splitArms(values: List<String>): List<String> {
        val index=values.indexOf("手臂")
        return if(index<0) (values+arms).distinct() else (values.take(index).filterNot {it in arms}+arms+values.drop(index+1).filterNot {it in arms}).distinct()
    }
    fun refineArms(values: List<String>, text: String, catalog: List<String> = parts): List<String> {
        if("手臂" !in values) return values
        val ambiguous=listOf("不","没","未","无","勿","别","非","取消","跳过","略过","放弃","排除","避免","除外","休息","停练","计划","准备","打算","想","待","可能","也许","或","是否","其中","之一","？","?","下次","明天","明日","后天","下周","改天","上次","之前","以前","昨天","昨日")
        if(ambiguous.any {it in text}) return values
        val mentioned=arms.filter {it in text}
        return if(mentioned.isEmpty()) values else normalized(values.filterNot {it=="手臂"}+mentioned,catalog)
    }
    fun description(record: Record)=listOf(record.json.optString("note"),record.json.optJSONArray("exercises")?.objects().orEmpty().joinToString("、") {it.optString("name")}).joinToString("、")
    fun review(reply: JSONObject, records: List<Record>, focusedPart: String? = null, catalog: List<String> = parts): PartPlan {
        val originals=records.associateBy {it.id.lowercase()}
        require(originals.size==records.size) {"训练编号重复"}
        val changes=reply.getJSONArray("changes").objects()
        require(changes.size<=30 && changes.map {it.getString("id").lowercase()}.distinct().size==changes.size) {"AI 返回重复或过多的修改，请重新生成预览"}
        val validated=changes.map {change ->
            val record=originals[change.getString("id").lowercase()] ?: error("AI 修改超出当前记录范围")
            require(focusedPart==null || focusedPart in of(record)) {"AI 修改超出当前部位范围"}
            val values=change.getJSONArray("bodyParts").strings()
            require(values.size<=30 && values.all(::valid) && values.distinct().size==values.size) {"AI 返回的部位格式无效"}
            PartChange(record.id,normalized(values,catalog))
        }.filter {it.bodyParts!=normalized(of(originals.getValue(it.id.lowercase())),catalog)}
        return PartPlan(reply.optString("answer"),validated,records.map {it.copy()})
    }
    fun classification(reply: JSONObject, records: List<Record>, catalog: List<String>): PartPlan {
        val values=reply.getJSONArray("suggestions").objects()
        require(values.size==records.size && values.map {it.getString("id").lowercase()}.toSet()==records.map {it.id.lowercase()}.toSet()) {"AI 分类编号与待分类记录不一致"}
        val available=(catalog+arms).distinct()
        val adjusted=values.map {value ->
            val selected=value.getJSONArray("bodyParts").strings()
            require(selected.all {it in available} && selected.distinct().size==selected.size) {"AI 分类包含未提供的部位"}
            val record=records.single {it.id.equals(value.getString("id"),true)}
            value.copy().put("bodyParts",JSONArray(refineArms(selected,description(record),catalog)))
        }
        return review(JSONObject().put("changes",JSONArray(adjusted)),records,catalog=catalog)
    }
    fun apply(snapshot: Snapshot, plan: PartPlan, allowedIDs: Set<String>, focusedPart: String? = null): Snapshot {
        require(plan.changes.map {it.id}.distinct().size==plan.changes.size && plan.changes.size<=plan.originals.size) {"修改预览无效"}
        val changes=plan.changes.associateBy {it.id}
        plan.changes.forEach {change ->
            val original=plan.originals.singleOrNull {it.id==change.id} ?: error("修改预览无效")
            val current=snapshot.records.singleOrNull {it.id==change.id && it.type==RecordType.WORKOUT} ?: error("训练记录已变化，请重新生成预览")
            require(current.id in allowedIDs && (focusedPart==null || focusedPart in of(current)) && canonical(current.json)==canonical(original.json)) {"训练记录已变化，请重新生成预览"}
            require(change.bodyParts.size<=30 && change.bodyParts.all(::valid) && change.bodyParts.distinct().size==change.bodyParts.size) {"部位格式无效"}
        }
        return snapshot.copy(records=snapshot.records.map {r -> changes[r.id]?.takeIf {r.type==RecordType.WORKOUT}?.let {change ->r.copy().apply {json.put("bodyParts",JSONArray(change.bodyParts));json.put("updatedAt",now());Validation.record(this)}} ?: r})
    }
    fun rename(snapshot: Snapshot, catalog: List<String>, old: String, name: String): Pair<Snapshot,List<String>> {
        require(valid(name)) {"名称需在 30 字以内，不包含换行"}
        val existing=catalog+snapshot.records.flatMap {of(it)+it.json.optJSONArray("exercises")?.objects().orEmpty().map {ex->ex.optString("bodyPart")}+listOf(it.json.optString("bodyPart"))}
        require(name==old || existing.none {it!=old && it.equals(name,true)}) {"部位名称已存在"}
        if(name==old) return snapshot to catalog
        val records=snapshot.records.map {r ->
            if(r.type !in listOf(RecordType.WORKOUT,RecordType.EXERCISE)) r else {
                val copy=r.copy();var changed=false
                if(old in of(r)) {copy.json.put("bodyParts",JSONArray(of(r).map {if(it==old) name else it}));changed=true}
                val exercises=r.json.optJSONArray("exercises")?.objects()
                if(exercises?.any {it.optString("bodyPart")==old}==true) {copy.json.put("exercises",JSONArray(exercises.map {it.copy().apply {if(optString("bodyPart")==old) put("bodyPart",name)}}));changed=true}
                if(r.type==RecordType.EXERCISE && r.json.optString("bodyPart")==old) {copy.json.put("bodyPart",name);changed=true}
                if(changed) {copy.json.put("updatedAt",now());Validation.record(copy);copy} else r
            }
        }
        return snapshot.copy(records=records) to (if(old in catalog) catalog.map {if(it==old) name else it} else catalog+name)
    }
}
