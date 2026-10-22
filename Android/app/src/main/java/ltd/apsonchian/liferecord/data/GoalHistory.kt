package ltd.apsonchian.liferecord.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** Stable version IDs keep a correction (including a moved date) from being undone by stale sync. */
object GoalHistory {
    const val baselineDay="1970-01-01"
    val fields=listOf("fitnessGoal","baselineWeight","targetWeight","weeklyWeightTarget","calorieGoal","proteinGoal","carbsGoal","fatGoal")
    private fun entries(profile:JSONObject)=profile.optJSONArray("goalHistory")?.objects().orEmpty()
    private fun values(profile:JSONObject)=JSONObject().apply {fields.forEach {put(it,profile.get(it))}}
    private fun same(a:JSONObject,b:JSONObject)=fields.all {a.opt(it)==b.opt(it) || (a.opt(it) is Number && b.opt(it) is Number && a.getDouble(it)==b.getDouble(it))}
    private fun rank(v:JSONObject)=maxOf(v.getDouble("updatedAt"),v.optDouble("revisionAt",0.0))
    private val order=compareBy<JSONObject> {rank(it)}.thenBy {it.optString("revisionID",it.getString("id"))}.thenBy {it.getString("id")}
    private fun winner(items:List<JSONObject>):JSONObject {
        if(items.all {it.getString("effectiveDate")==baselineDay}) {
            val revisions=items.filter {it.has("revisionAt")}
            if(revisions.isNotEmpty()) return revisions.maxWith(order)
            return items.minWith(compareBy<JSONObject> {it.getDouble("updatedAt")}.thenBy {it.getString("id")})
        }
        return items.maxWith(order)
    }
    fun merge(vararg profiles:JSONObject):JSONArray = JSONArray(profiles.flatMap(::entries).groupBy {it.getString("id")}.values.map(::winner)
        .sortedWith(compareBy<JSONObject> {it.getString("effectiveDate")}.then(order)).map {it.copy()})
    fun versions(profile:JSONObject):List<JSONObject> = merge(profile).objects().groupBy {it.getString("effectiveDate")}.toSortedMap().values.map(::winner)
    fun validate(profile:JSONObject) {
        if(!profile.has("goalHistory")) return
        require(profile.opt("goalHistory") is JSONArray) {"目标历史需要数组"}
        entries(profile).forEach {v ->
            val day=LocalDate.parse(v.getString("effectiveDate"));require(day>=LocalDate.of(1970,1,1))
            Validation.number(v,"updatedAt",0.0,4102444800.0)
            if(v.has("revisionAt")) Validation.number(v,"revisionAt",0.0,4102444800.0)
            if(v.has("revisionID")) require(v.opt("revisionID") is String && v.getString("revisionID").isNotBlank())
            require(v.opt("id") is String && v.getString("id").isNotBlank())
            require(v.opt("fitnessGoal") is String)
            fields.drop(1).forEach {key ->require(v.opt(key) is Number && v.getDouble(key).isFinite())}
        }
    }
    fun at(profile:JSONObject,day:LocalDate):JSONObject {
        val list=versions(profile)
        val version=list.lastOrNull {it.getString("effectiveDate")<=day.toString()} ?: list.firstOrNull()
        return profile.copy().apply {version?.let {v ->fields.forEach {put(it,v.get(it))}}}
    }
    fun weightStageStart(profile:JSONObject,day:LocalDate):LocalDate? {
        var previous:JSONObject?=null
        var start:LocalDate?=null
        versions(profile).filter {it.getString("effectiveDate")<=day.toString()}.forEach {v ->
            if(previous==null || fields.take(4).any {key ->previous!!.opt(key)!=v.opt(key) && !(previous!!.opt(key) is Number && v.opt(key) is Number && previous!!.getDouble(key)==v.getDouble(key))}) start=v.getString("effectiveDate").takeUnless {it==baselineDay}?.let(LocalDate::parse)
            previous=v
        }
        return start
    }
    private fun nextStamp(profile:JSONObject,stamp:Double)=maxOf(stamp,profile.optDouble("updatedAt")+.001,(entries(profile).maxOfOrNull(::rank) ?: 0.0)+.001)
    fun changed(previous:JSONObject,next:JSONObject,stamp:Double=now(),day:LocalDate=stamp.day()):JSONObject {
        val writtenAt=nextStamp(previous,stamp)
        val history=merge(previous,next)
        if(!same(previous,next)) {
            if(history.length()==0) history.put(values(previous).put("id","baseline").put("effectiveDate",baselineDay).put("updatedAt",previous.getDouble("updatedAt")))
            val existing=versions(JSONObject().put("goalHistory",history)).firstOrNull {it.getString("effectiveDate")==day.toString()}
            history.put(values(next).put("id",existing?.getString("id") ?: UUID.randomUUID().toString().lowercase()).put("effectiveDate",day.toString()).put("updatedAt",writtenAt))
        }
        return next.copy().put("updatedAt",writtenAt).put("goalTimeZone",ZoneId.systemDefault().id)
            .apply {if(history.length()>0) put("goalHistory",merge(JSONObject().put("goalHistory",history)))}
    }
    fun revised(profile:JSONObject,expected:JSONObject,next:JSONObject,day:LocalDate,stamp:Double=now(),today:LocalDate=LocalDate.now()):JSONObject {
        val actual=versions(profile).firstOrNull {it.getString("id")==expected.getString("id")} ?: error("该目标记录已更新，请重新打开")
        require(same(actual,expected) && actual.getString("effectiveDate")==expected.getString("effectiveDate") && rank(actual)==rank(expected) && actual.optString("revisionID")==expected.optString("revisionID")) {"该目标记录已更新，请重新打开"}
        val baseline=actual.getString("effectiveDate")==baselineDay
        require(if(baseline) day.toString()==baselineDay else day>LocalDate.parse(baselineDay) && day<=today) {"请选择今天或更早的生效日期"}
        require(versions(profile).none {it.getString("id")!=actual.getString("id") && it.getString("effectiveDate")==day.toString()}) {"该日期已有目标记录，请编辑那条记录或选择其他日期"}
        Validation.profile(profile.copy().apply {fields.forEach {put(it,next.get(it))}})
        val writtenAt=nextStamp(profile,stamp)
        val correction=actual.copy().apply {fields.forEach {put(it,next.get(it))}}.put("effectiveDate",day.toString()).put("revisionAt",writtenAt).put("revisionID",UUID.randomUUID().toString().lowercase())
        val merged=profile.copy().put("goalHistory",merge(profile,JSONObject().put("goalHistory",JSONArray().put(correction))))
        return at(merged,today).put("updatedAt",writtenAt).put("goalTimeZone",ZoneId.systemDefault().id)
    }
    fun mergedProfile(local:JSONObject,remote:JSONObject):JSONObject {
        val winner=if(remote.optDouble("updatedAt")>local.optDouble("updatedAt")) remote else local
        val history=merge(local,remote)
        val merged=winner.copy().apply {if(history.length()>0) put("goalHistory",history)}
        return if(history.objects().any {it.has("revisionAt")}) at(merged,LocalDate.now()) else merged
    }
}
