package ltd.apsonchian.liferecord.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** Civil dates are intentional: travelling must not move a goal to another day. */
object GoalHistory {
    val fields=listOf("fitnessGoal","baselineWeight","targetWeight","weeklyWeightTarget","calorieGoal","proteinGoal","carbsGoal","fatGoal")
    private fun values(profile:JSONObject)=JSONObject().apply {fields.forEach {put(it,profile.get(it))}}
    private fun same(a:JSONObject,b:JSONObject)=fields.all {a.opt(it)==b.opt(it) || (a.opt(it) is Number && b.opt(it) is Number && a.getDouble(it)==b.getDouble(it))}
    fun versions(profile:JSONObject):List<JSONObject> = profile.optJSONArray("goalHistory")?.objects().orEmpty().sortedBy {it.getString("effectiveDate")}
    fun validate(profile:JSONObject) {
        if(!profile.has("goalHistory")) return
        require(profile.opt("goalHistory") is JSONArray) {"目标历史需要数组"}
        versions(profile).forEach {v ->
            val day=LocalDate.parse(v.getString("effectiveDate"));require(day>=LocalDate.of(1970,1,1))
            Validation.number(v,"updatedAt",0.0,4102444800.0)
            require(v.opt("id") is String && v.getString("id").isNotBlank())
            require(v.opt("fitnessGoal") is String)
            fields.drop(1).forEach {key ->require(v.opt(key) is Number && v.getDouble(key).isFinite())}
        }
    }
    fun merge(vararg profiles:JSONObject):JSONArray {
        val entries=profiles.flatMap(::versions).groupBy {it.getString("effectiveDate")}.toSortedMap()
        return JSONArray(entries.map { (date,items) ->
            // The migration baseline represents the oldest known target.
            (if(date=="1970-01-01") items.minWith(compareBy<JSONObject> {it.getDouble("updatedAt")}.thenBy {it.getString("id")})
             else items.maxWith(compareBy<JSONObject> {it.getDouble("updatedAt")}.thenBy {it.getString("id")})).copy()
        })
    }
    fun at(profile:JSONObject,day:LocalDate):JSONObject {
        val entries=versions(profile)
        val version=entries.lastOrNull {it.getString("effectiveDate")<=day.toString()} ?: entries.firstOrNull()
        return profile.copy().apply {version?.let {v ->fields.forEach {put(it,v.get(it))}}}
    }
    fun weightStageStart(profile:JSONObject,day:LocalDate):LocalDate? {
        var previous:JSONObject?=null
        var start:LocalDate?=null
        versions(profile).filter {it.getString("effectiveDate")<=day.toString()}.forEach {v ->
            if(previous==null || fields.take(4).any {key ->previous!!.opt(key)!=v.opt(key) && !(previous!!.opt(key) is Number && v.opt(key) is Number && previous!!.getDouble(key)==v.getDouble(key))}) start=v.getString("effectiveDate").takeUnless {it=="1970-01-01"}?.let(LocalDate::parse)
            previous=v
        }
        return start
    }
    fun changed(previous:JSONObject,next:JSONObject,stamp:Double=now(),day:LocalDate=stamp.day()):JSONObject {
        val writtenAt=maxOf(stamp,previous.optDouble("updatedAt")+.001)
        val history=merge(previous,next)
        if(!same(previous,next)) {
            if(history.length()==0) history.put(values(previous).put("id","baseline").put("effectiveDate","1970-01-01").put("updatedAt",previous.getDouble("updatedAt")))
            history.put(values(next).put("id",UUID.randomUUID().toString().lowercase()).put("effectiveDate",day.toString()).put("updatedAt",writtenAt))
        }
        return next.copy().put("updatedAt",writtenAt).put("goalTimeZone",ZoneId.systemDefault().id)
            .apply {if(history.length()>0) put("goalHistory",merge(JSONObject().put("goalHistory",history)))}
    }
    fun mergedProfile(local:JSONObject,remote:JSONObject):JSONObject {
        val winner=if(remote.optDouble("updatedAt")>local.optDouble("updatedAt")) remote else local
        val history=merge(local,remote)
        return winner.copy().apply {if(history.length()>0) put("goalHistory",history)}
    }
}
