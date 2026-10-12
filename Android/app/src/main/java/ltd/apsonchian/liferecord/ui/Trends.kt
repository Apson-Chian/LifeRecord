package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import java.time.LocalDate
import kotlin.math.abs

@Composable fun Trends(vm: AppViewModel,s:Snapshot,detail:(Record)->Unit,report:()->Unit) {
    var range by remember { mutableIntStateOf(30) }; var search by remember { mutableStateOf("") }; var filter by remember { mutableStateOf<RecordType?>(null) }
    val today=LocalDate.now(); val start=if(range==0) LocalDate.MIN else today.minusDays(range.toLong()-1)
    val records=s.records.filter { !it.demo && it.date.day() in start..today }
    val meals=records.filter { it.type==RecordType.MEAL }; val weights=Insights.weights(records)
    val workouts=records.filter { it.type==RecordType.WORKOUT }.sortedByDescending { it.date }
    val days=meals.map { it.date.day() }.distinct().size
    val quality=records.flatMap { r -> Insights.quality(r).map { r to it } }
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
        item { PageTitle("看见你的进步","身体的变化，需要时间") }
        item { Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) { listOf(7 to "7 天",30 to "30 天",0 to "全部").forEach { (value,label) -> FilterChip(selected=range==value,onClick={range=value},label={Text(label)}) } } }
        item { Panel {
            Text("训练概览",style=MaterialTheme.typography.titleLarge)
            val complete=workouts.filter { !it.json.isNull("endDate") }
            Text("${complete.size} 次完成 · ${format(complete.sumOf { (it.json.optDouble("endDate")-it.date)/60 })} 分钟",style=MaterialTheme.typography.headlineMedium)
            if(workouts.isEmpty()) Text("这一时段还没有训练记录",color=MaterialTheme.colorScheme.onSurfaceVariant)
            workouts.take(5).forEach { RecordRow(it,{detail(it)}) }
            val byPart=workouts.flatMap { it.json.optJSONArray("bodyParts")?.strings().orEmpty() }.groupingBy { it }.eachCount()
            if(byPart.isNotEmpty()) Text(byPart.entries.sortedByDescending { it.value }.joinToString(" · ") { "${it.key} ${it.value} 次" },style=MaterialTheme.typography.bodyMedium)
        } }
        item { Panel {
            Text("体重趋势",style=MaterialTheme.typography.titleLarge)
            if(weights.isEmpty()) Empty("等待第一次测量","记下体重，慢慢看见变化") else {
                Text("${format(weights.last().second)} kg",style=MaterialTheme.typography.headlineMedium)
                LineChart(weights.map { it.second },weights.map { it.first.toEpochDay().toDouble() })
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) { Text(weights.first().first.toString(),style=MaterialTheme.typography.labelSmall); Text(weights.last().first.toString(),style=MaterialTheme.typography.labelSmall) }
                Text("按测量日期绘制；同一天多次测量取中位数。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } }
        item { Panel {
            Text("近 14 天热量",style=MaterialTheme.typography.titleLarge)
            val values=(13L downTo 0L).map { day -> val entries=Insights.daily(s.records.filter { !it.demo },today.minusDays(day)); if(entries.isEmpty()) null else Insights.total(entries,"calories") }
            BarChart(values,s.profile.optDouble("calorieGoal")); Text("有记录的日期才计入；空白日期表示未记录。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            Text("当前时段 · $days 天记录饮食 · ${if(days>0) format(Insights.total(meals,"calories")/days) else "—"} kcal / 记录日",style=MaterialTheme.typography.bodyMedium)
        } }
        item { Panel {
            Text("一起做一次复盘",style=MaterialTheme.typography.titleLarge); Text("用最近七天的饮食与训练，和教练制定下一步。",color=MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick=report,Modifier.fillMaxWidth()) { Text("生成 AI 周报") }
        } }
        item { Panel {
            Text("目标反馈",style=MaterialTheme.typography.titleLarge)
            val goal=s.profile.optDouble("targetWeight")
            if(weights.isNotEmpty()) Text("距目标 ${format(goal)} kg：${format(abs(weights.last().second-goal))} kg") else Text("还没有真实测量，暂时无法反馈身体变化。")
            Text("饮食覆盖 $days 天；蛋白质达标 ${meals.groupBy { it.date.day() }.count { Insights.total(it.value,"protein") >= s.profile.optDouble("proteinGoal") }} 天。")
            Text("有记录不代表当天记全。缺失日期不按零摄入计算；今日结果仍可能变化。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            if(days<minOf(if(range==0) 7 else range,3)) Text("下一步：先提高记录覆盖，暂时不要根据零散记录调整目标。")
            val recent=weights.filter { it.first>=today.minusDays(6) }
            if(recent.size>=3 && java.time.temporal.ChronoUnit.DAYS.between(recent.first().first,recent.last().first)>=6) Text("一周测量变化 ${format(recent.last().second-recent.first().second)} kg；设定每周目标 ${format(s.profile.optDouble("weeklyWeightTarget"))} kg。")
        } }
        if(quality.isNotEmpty()) item { Panel { Text("记录质量检查",style=MaterialTheme.typography.titleLarge); quality.take(10).forEach { (r,message) -> TextButton(onClick={detail(r)}) { Text("${r.title}：$message") } }; Text("这些是核对线索，不会自动修改记录。",style=MaterialTheme.typography.bodySmall) } }
        item { Text("全部记录",style=MaterialTheme.typography.titleLarge); Spacer(Modifier.height(12.dp)); OutlinedTextField(search,{search=it},Modifier.fillMaxWidth(),label={Text("搜索名称、备注与部位")},singleLine=true) }
        item { Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) { FilterChip(filter==null,{filter=null},label={Text("全部")}); listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT).forEach { t -> FilterChip(filter==t,{filter=t},label={Text(t.label)}) } } }
        val visible=records.filter { it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) && (filter==null || it.type==filter) && (search.isBlank() || it.title.contains(search,true) || it.json.optString("note").contains(search,true)) }.sortedByDescending { it.date }
        if(visible.isEmpty()) item { Empty("没有符合条件的记录","调整范围或搜索内容") }
        items(visible,key={it.type.name+it.id}) { r -> Panel { RecordRow(r,{detail(r)}) } }
    }
}
@Composable fun LineChart(values:List<Double>,dates:List<Double>) {
    val grid=MaterialTheme.colorScheme.surfaceVariant; val color=MaterialTheme.colorScheme.primary
    Canvas(Modifier.fillMaxWidth().height(150.dp)) {
        val min=values.min()-0.3; val max=values.max()+0.3; val span=(dates.last()-dates.first()).coerceAtLeast(1.0)
        repeat(4) { val y=size.height*it/3; drawLine(grid,Offset(0f,y),Offset(size.width,y),1.dp.toPx()) }
        val points=values.mapIndexed { i,v -> Offset(((dates[i]-dates.first())/span*size.width).toFloat(), (size.height*(1-(v-min)/(max-min))).toFloat()) }
        val path=Path(); points.forEachIndexed { i,p -> if(i==0) path.moveTo(p.x,p.y) else path.lineTo(p.x,p.y) }
        drawPath(path,color,style=Stroke(3.dp.toPx(),cap=StrokeCap.Round)); points.forEach { drawCircle(color,4.dp.toPx(),it) }
    }
}
@Composable fun BarChart(values:List<Double?>,goal:Double) {
    val color=MaterialTheme.colorScheme.primary; val empty=MaterialTheme.colorScheme.surfaceVariant
    Canvas(Modifier.fillMaxWidth().height(130.dp)) {
        val max=maxOf(goal,values.filterNotNull().maxOrNull() ?: goal)*1.15
        val width=size.width/values.size; val y=(size.height*(1-goal/max)).toFloat()
        drawLine(Meals,Offset(0f,y),Offset(size.width,y),1.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(8f,8f)))
        values.forEachIndexed { i,v -> val h=if(v==null) 3.dp.toPx() else (v/max*size.height).toFloat(); drawRoundRect(if(v==null) empty else color,Offset(i*width+width*0.2f,size.height-h),androidx.compose.ui.geometry.Size(width*0.6f,h),androidx.compose.ui.geometry.CornerRadius(4.dp.toPx())) }
    }
}
