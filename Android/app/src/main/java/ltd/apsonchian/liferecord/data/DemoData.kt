package ltd.apsonchian.liferecord.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalTime
import java.util.UUID
import kotlin.math.sin

/** Synthetic local examples. Their flags must survive edits and never reach sync. */
object DemoData {
    private val trackedTypes = setOf(RecordType.MEAL, RecordType.BODY, RecordType.WORKOUT)
    fun isPreview(records: List<Record>) = records.any { it.demo && it.type in trackedTypes } &&
        records.none { !it.demo && it.type in trackedTypes }

    /** Preview goals never overwrite the user's personal profile. */
    fun profile() = defaultProfile().put("displayName", "").put("fitnessGoal", "维持")
        .put("baselineWeight", 69.0).put("targetWeight", 68.5).put("calorieGoal", 2200.0)
        .put("proteinGoal", 130.0).put("carbsGoal", 270.0).put("fatGoal", 70.0)

    private data class Meal(val name: String, val protein: Double, val carbs: Double, val fat: Double, val fiber: Double, val portion: String)
    private val breakfasts = listOf(
        Meal("燕麦鸡蛋牛奶碗",28.0,61.0,17.0,7.0,"燕麦 50g、牛奶 250ml、鸡蛋 1 个、香蕉半根"),
        Meal("全麦吐司与煎蛋",25.0,53.0,18.0,6.0,"全麦吐司 2 片、煎蛋 2 个、番茄 1 个"),
        Meal("豆浆杂粮包",24.0,69.0,13.0,8.0,"无糖豆浆 300ml、杂粮包 2 个、鸡蛋 1 个"),
        Meal("酸奶莓果麦片",27.0,58.0,15.0,8.0,"原味酸奶 250g、麦片 40g、莓果 100g、核桃 10g")
    )
    private val lunches = listOf(
        Meal("鸡胸肉糙米饭",43.0,84.0,19.0,8.0,"鸡胸肉 130g、熟糙米饭 220g、时蔬 200g"),
        Meal("番茄牛肉意面",37.0,88.0,22.0,7.0,"瘦牛肉 100g、干意面 100g、番茄蘑菇 200g"),
        Meal("虾仁杂粮饭",39.0,79.0,16.0,9.0,"虾仁 150g、熟杂粮饭 200g、彩椒西兰花 200g"),
        Meal("香菇鸡腿饭",38.0,82.0,23.0,7.0,"去骨鸡腿 130g、熟米饭 200g、香菇青菜 200g"),
        Meal("豆腐荞麦面",31.0,86.0,20.0,10.0,"豆腐 150g、荞麦面 100g、毛豆与绿叶菜 200g")
    )
    private val dinners = listOf(
        Meal("三文鱼藜麦碗",38.0,65.0,25.0,9.0,"三文鱼 120g、熟藜麦 180g、烤南瓜与生菜 200g"),
        Meal("鸡腿红薯西兰花",39.0,72.0,22.0,11.0,"去皮鸡腿 140g、红薯 250g、西兰花 200g"),
        Meal("清蒸鲈鱼与米饭",42.0,68.0,17.0,7.0,"鲈鱼可食部 160g、熟米饭 180g、青菜 200g"),
        Meal("牛肉土豆炖菜",36.0,75.0,24.0,9.0,"瘦牛肉 120g、土豆 250g、胡萝卜与洋葱 200g"),
        Meal("菌菇豆腐杂粮碗",32.0,78.0,21.0,12.0,"豆腐 180g、熟杂粮饭 180g、菌菇蔬菜 200g")
    )
    private val snacks = listOf(
        Meal("酸奶蓝莓坚果",20.0,31.0,12.0,5.0,"高蛋白酸奶 150g、蓝莓 80g、坚果 15g"),
        Meal("牛奶香蕉",16.0,38.0,9.0,3.0,"牛奶 300ml、香蕉 1 根"),
        Meal("奶酪全麦三明治",22.0,35.0,11.0,4.0,"全麦面包 2 片、奶酪 1 片、鸡胸肉 40g"),
        Meal("豆乳与毛豆",21.0,24.0,13.0,6.0,"无糖豆乳 250ml、去壳毛豆 80g")
    )

    fun records(at: Double = now()): List<Record> = buildList {
        fun record(type: RecordType, date: Double, configure: JSONObject.() -> Unit): Record =
            Record.create(type, date).apply { json.put("isDemo", true).put("createdAt",date).put("updatedAt",at); json.configure() }
        var session = 0
        for (offset in 29 downTo 0) {
            val day = at.day().minusDays(offset.toLong())
            fun time(hour: Int, minute: Int = 0) = day.epochAt(LocalTime.of(hour, minute))
            val progress = (29 - offset).toDouble()
            if (offset !in listOf(9,18) && time(7,20) <= at) {
                add(record(RecordType.BODY, time(7,20)) {
                    put("weight", 69.0-progress*.017+sin(progress/2.1)*.22)
                    if (offset%4!=1) put("bodyFat",18.2-progress*.018+sin(progress/3)*.16)
                    if (offset%3==0) put("waist",79.0-progress*.025)
                    put("note","[示例] 晨起、早餐前测量；单日波动与长期趋势分开看")
                })
                if (offset in listOf(7,21) && time(20,30)<=at) add(record(RecordType.BODY,time(20,30)) {
                    put("weight",69.0-progress*.017+.65);put("note","[示例] 晚间补测；同日多次测量用于体验中位数")
                })
            }
            val trainingDay = offset%7 !in listOf(2,5)
            if (offset != 11) {
                fun meal(kind: String, sample: Meal, hour: Int, minute: Int, portion: Double = 1.0) {
                    if(time(hour,minute)>at) return
                    add(record(RecordType.MEAL,time(hour,minute)) {
                        put("kind",kind);put("name",sample.name)
                        put("protein",sample.protein*portion);put("carbs",sample.carbs*portion)
                        put("fat",sample.fat*portion);put("fiber",sample.fiber*portion)
                        put("calories",(sample.protein*4+sample.carbs*4+sample.fat*9)*portion)
                        put("inputText",sample.portion);put("source","手动")
                        put("note","[示例] ${sample.portion}；合成营养值，用于体验份量与记录，不是饮食建议")
                    })
                }
                val variation = listOf(.90,1.0,1.08,1.16)[offset%4]
                meal("早餐",breakfasts[offset%breakfasts.size],7+offset%2,35,variation)
                meal("午餐",lunches[offset%lunches.size],12,10+offset%4*5,variation)
                if(offset!=10) meal("晚餐",dinners[(offset+2)%dinners.size],19,10,if(trainingDay) 1.12 else .95)
                if(trainingDay || offset%4==0) meal("加餐",snacks[offset%snacks.size],16,5)
            }
            if (trainingDay && time(18,50)<=at) {
                val split=session++%5
                val groups=listOf(listOf("胸部","三头"),listOf("背部","二头"),listOf("臀腿","核心"),listOf("肩部","小臂"),listOf("有氧","核心"))[split]
                val names=listOf(listOf("哑铃卧推","绳索下压"),listOf("高位下拉","哑铃弯举"),listOf("高脚杯深蹲","平板支撑"),listOf("哑铃推举","锤式弯举"),listOf("椭圆机","平板支撑"))[split]
                val minutes=if(split==4) 38 else 42+offset%4*5
                add(record(RecordType.WORKOUT,time(18,50)-minutes*60) {
                    put("endDate",time(18,50));put("bodyParts",JSONArray(groups))
                    put("exercises",JSONArray(names.mapIndexed { index,name ->
                        val timed=name in listOf("椭圆机","平板支撑")
                        JSONObject().put("name",name).put("bodyPart",groups[index]).put("sets",JSONArray(
                            (0 until if(name=="椭圆机") 1 else 3).map { set ->
                                if(timed) JSONObject().put("durationSeconds",if(name=="椭圆机") 1800 else 40+set*5)
                                else JSONObject().put("reps",12-set*2).put("weight",(if(split==1 && index==0) 25 else 10)+progress.toInt()/10*2)
                            }
                        ))
                    }))
                    put("note","[示例] ${groups.joinToString(" / ")} · ${if(split==4) "计时与核心" else "逐组记录，逐步增加负重"}")
                })
            }
        }
        breakfasts.take(3).forEach { sample -> add(record(RecordType.FAVORITE,at) {
            put("name","[示例] ${sample.name}");put("protein",sample.protein);put("carbs",sample.carbs);put("fat",sample.fat);put("fiber",sample.fiber)
            put("calories",sample.protein*4+sample.carbs*4+sample.fat*9);put("note",sample.portion)
        }) }
        listOf("哑铃卧推" to "胸部","高位下拉" to "背部","高脚杯深蹲" to "臀腿","平板支撑" to "核心").forEach { (name,part) ->
            add(record(RecordType.EXERCISE,at) {put("name","[示例] $name");put("bodyPart",part);put("sets",3);put("note","[示例] 可查看或在新训练中选用")})
        }
    }

    fun conversations(at: Double = now()): List<JSONObject> {
        fun chat(title: String, question: String, answer: String, timestamp: Double) = JSONObject()
            .put("id", UUID.randomUUID().toString()).put("title", "[示例] $title").put("isDemo", true)
            .put("messages", JSONArray(listOf(
                CoachGeneration.question(question, question, emptyList(), timestamp - 60).put("generationState", "completed"),
                JSONObject().put("id", UUID.randomUUID().toString()).put("role", "assistant").put("content", answer).put("createdAt", timestamp)
            )))
        val examples=records(at)
        val meals=examples.filter {it.type==RecordType.MEAL}
        val workouts=examples.filter {it.type==RecordType.WORKOUT}
        val measuredDays=examples.filter {it.type==RecordType.BODY}.map {it.date.day()}.distinct().size
        val overview="这是按本次合成示例预先整理的导览，不是实时 AI 回答。\n\n这 30 天内有 ${meals.size} 餐、$measuredDays 天身体测量和 ${workouts.size} 次训练。\n\n饮食：早餐、午餐、晚餐与加餐有不同组合和份量，留有漏记日期。示例目标是 2200 千卡、蛋白质 130g；目标只用于预览，不会修改你的个人设置。\n\n身体：晨起体重有日间波动，另有两天晚间补测。在身体总览比较灰色中位数和强调色趋势，不把一次升降当作长期变化。\n\n训练：轮换胸/三头、背/二头、臀腿/核心、肩/小臂及有氧，包含休息日、负重次数和计时组。点开日历即可查看逐组记录。\n\n连接 AI 后可以继续追问这些示例；示例对话只读。开始记录自己的数据后，新建对话会读取全部本机真实记录。"
        return listOf(
            chat("看懂一个月的记录", "帮我回顾这些饮食、身体与训练示例", overview, at),
            chat("从第一餐开始", "我该怎样开始记录？", "这是预先写好的使用示例。\n\n1. 在「今日」点添加，手动记一餐或一次测量。\n2. 训练时点「开始训练」，结束后可补充动作和组数。\n3. 在「设置」填写自己的目标，需要时再连接同步与 AI 服务。\n\n示例可随时在设置中清除；清除后，你自己的记录会保留。", at - 120)
        )
    }
}
