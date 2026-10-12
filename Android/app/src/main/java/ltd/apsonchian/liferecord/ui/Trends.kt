@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import kotlinx.coroutines.delay
import java.time.*
import kotlin.math.abs

@Composable fun Trends(vm: AppViewModel,s:Snapshot,detail:(Record)->Unit,coach:(String)->Unit,notify:(String)->Unit) {
    var range by rememberSaveable { mutableIntStateOf(30) }
    var details by rememberSaveable { mutableStateOf(false) }
    var measurement by rememberSaveable { mutableStateOf<String?>(null) }
    var quality by rememberSaveable { mutableStateOf(false) }
    var showReport by rememberSaveable { mutableStateOf(false) }
    var at by remember { mutableDoubleStateOf(now()) }
    LaunchedEffect(Unit) { while(true) { delay(60_000); at=now() } }
    val acknowledged by vm.acknowledgedQuality.collectAsState()
    val report by vm.weeklyReport.collectAsState()
    val today=at.day(); val start=if(range==0) LocalDate.MIN else today.minusDays(range.toLong()-1)
    val real=s.records.filter { !it.demo && it.date<=at }
    val records=real.filter { it.date.day()>=start }
    val meals=records.filter { it.type==RecordType.MEAL && RecordQuality.validNutrition(it) }
    val weights=BodyTrend.records(real,"weight",at).filter { it.day>=start }
    val fat=BodyTrend.records(real,"bodyFat",at).filter { it.day>=start }
    val workouts=records.filter { it.type==RecordType.WORKOUT }.sortedByDescending { it.date }
    val feedback=GoalFeedback.summarize(s.records,s.profile,range,at,acknowledged)
    val pending=RecordQuality.issues(s.records,at).filter { it.id !in acknowledged }
    if(details) { RecordDataDetails(s,s.records.filter { !it.demo && it.date.day()>=start },{details=false},detail); return }
    measurement?.let { field -> MeasurementDetail(real,field,start,{measurement=null},detail); return }
    if(quality) { QualityReview(vm,s,{quality=false},detail,notify); return }
    if(showReport) { SubPage("AI 周报",{showReport=false}) {
        report.generatedAt?.let { Text("生成于 ${it.localText()} · 最近七天",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        SelectionContainer { MarkdownText(report.text) }
        Text("这份报告使用生成时的记录快照；记录变化后可重新生成。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }; return }
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp,20.dp,16.dp,glassPageBottomPadding()),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item { PageTitle("趋势","回顾训练与身体变化") { IconButton(onClick={details=true}) { Icon(Icons.AutoMirrored.Filled.List,"查看全部数据详情") } } }
        item { RangePicker(range) { range=it } }
        item { Panel {
            Text("训练概览",style=MaterialTheme.typography.titleLarge)
            val complete=workouts.filter { !it.json.isNull("endDate") && it.json.optDouble("endDate") in it.date..at }
            Text("${complete.size} 次完成 · ${format(complete.sumOf { (it.json.optDouble("endDate")-it.date)/60 })} 分钟",style=MaterialTheme.typography.headlineMedium)
            if(workouts.isEmpty()) Text("这一时段还没有训练记录",color=MaterialTheme.colorScheme.onSurfaceVariant)
            workouts.take(5).forEach { RecordRow(it,{detail(it)}) }
            val byPart=workouts.flatMap { it.json.optJSONArray("bodyParts")?.strings().orEmpty().ifEmpty {
                it.json.optJSONArray("exercises")?.objects()?.map { ex -> ex.optString("bodyPart","未分类") }?.distinct().orEmpty()
            } }.groupingBy { it }.eachCount()
            if(byPart.isNotEmpty()) Text(byPart.entries.sortedByDescending { it.value }.joinToString(" · ") { "${it.key} ${it.value} 次" },style=MaterialTheme.typography.bodyMedium)
            TextButton(onClick={details=true}) { Text("训练内容与全部明细") }
        } }
        item { Panel {
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) { Text("体重趋势",style=MaterialTheme.typography.titleLarge,modifier=Modifier.weight(1f)); TextButton(onClick={measurement="weight"},modifier=Modifier.testTag("weight-detail")) { Text("查看详情") } }
            if(weights.isEmpty()) Empty("等待第一次测量","记下体重，慢慢看见变化") else TrendChart(weights,"kg",MaterialTheme.colorScheme.primary,goal=s.profile.optDouble("targetWeight"))
        } }
        item { Panel {
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) { Text("体脂趋势",style=MaterialTheme.typography.titleLarge,modifier=Modifier.weight(1f)); TextButton(onClick={measurement="bodyFat"},modifier=Modifier.testTag("fat-detail")) { Text("查看详情") } }
            if(fat.isEmpty()) Empty("暂无体脂记录","测量后即可查看数值和变化") else TrendChart(fat,"%",Fat)
        } }
        item { Panel {
            Text("近 14 天热量",style=MaterialTheme.typography.titleLarge)
            val values=(13L downTo 0L).map { day -> val entries=Insights.daily(real.filter { it.type==RecordType.MEAL && RecordQuality.validNutrition(it) },today.minusDays(day)); if(entries.isEmpty()) null else Insights.total(entries,"calories") }
            BarChart(values,s.profile.optDouble("calorieGoal")); Text("有记录的日期才计入；空白日期表示未记录。今日仍可能变化。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            val mealDays=meals.map { it.date.day() }.distinct().size
            Text("当前时段 · $mealDays 天记录饮食 · ${if(mealDays>0) format(Insights.total(meals,"calories")/mealDays) else "—"} kcal / 记录日",style=MaterialTheme.typography.bodyMedium)
        } }
        item { Panel {
            Text("把记录，变成下一步",style=MaterialTheme.typography.titleLarge)
            Text(if(report.text.isEmpty()) "一份属于你的 AI 周报，发现变化，找到节奏。" else "本周复盘已就绪，查看趋势解读与行动建议。",color=MaterialTheme.colorScheme.onSurfaceVariant)
            if(report.text.isNotEmpty()) {
                report.generatedAt?.let { Text("生成于 ${it.localText()}",style=MaterialTheme.typography.bodySmall) }
                OutlinedButton(onClick={showReport=true},modifier=Modifier.fillMaxWidth()) { Text("阅读本周报告") }
            }
            if(report.error.isNotBlank()) Text(report.error,color=MaterialTheme.colorScheme.error)
            Button(onClick={vm.generateWeeklyReport()},enabled=!report.generating && real.any { it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) },modifier=Modifier.fillMaxWidth()) {
                if(report.generating) CircularProgressIndicator(Modifier.size(18.dp),strokeWidth=2.dp)
                Spacer(Modifier.width(8.dp)); Text(if(report.generating) "正在整理这一周…" else if(report.text.isEmpty()) "生成本周报告" else "重新生成")
            }
            if(real.isEmpty()) Text("先添加真实记录，示例不参与周报。",style=MaterialTheme.typography.bodySmall)
        } }
        item { FeedbackCard(feedback,s.profile) { coach("请依据我的设定目标与以下本机统计，复盘执行情况并给出下一周 2–3 条具体行动。先指出记录不足，不把体重变化当成脂肪或肌肉变化，不自动改动目标。\n${feedback.context}") } }
        item { Panel(Modifier.clickable { quality=true }) {
            Text("记录质量检查",style=MaterialTheme.typography.titleLarge)
            Text(if(pending.isEmpty()) "暂无待核对项 · 检查全部真实记录" else "${pending.size} 项待核对 · 查看疑点并修正",color=MaterialTheme.colorScheme.onSurfaceVariant)
        } }
    }

}

@Composable private fun FeedbackCard(summary:GoalFeedback.Summary,goals:org.json.JSONObject,coach:()->Unit) {
    Panel {
        Text("目标反馈",style=MaterialTheme.typography.titleLarge)
        Text("${summary.start} — ${now().day()}",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Text(summary.headline,style=MaterialTheme.typography.titleMedium)
        summary.latest?.let { latest ->
            Text("${format(latest.trend)} kg",style=MaterialTheme.typography.headlineMedium)
            Text("最近趋势体重 · ${latest.day} · 真实测量每日中位数平滑计算",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            summary.week?.let { week ->
                Text("本周进度 · ${week.start} — ${week.start.plusDays(6)}")
                LinearProgressIndicator(progress={week.fraction.toFloat()},modifier=Modifier.fillMaxWidth())
                Text("本周 ${(week.fraction*100).toInt()}% · 趋势变化 ${signed(week.change)} kg / 每周目标 ${format(goals.optDouble("weeklyWeightTarget"))} kg",style=MaterialTheme.typography.bodySmall)
                Text("每周一重算，以本周首次测量（${week.baseline}）为基准；体重进度不等同于增肌或减脂成果。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            summary.distance?.let { Text("距目标 ${format(goals.optDouble("targetWeight"))} kg：${format(it)} kg") }
            summary.weeklyChange?.let { Text("区间趋势折算 ${signed(it)} kg/周",style=MaterialTheme.typography.bodySmall) }
        }
        HorizontalDivider()
        FeedbackRow("饮食记录覆盖","${summary.mealDays} / ${summary.days} 天")
        FeedbackRow("热量在设定目标 ±10% 内","${summary.calorieDays} / ${summary.mealDays} 个记录日")
        FeedbackRow("蛋白质达到设定目标","${summary.proteinDays} / ${summary.mealDays} 个记录日")
        summary.calories?.let { FeedbackRow("已记录日均热量 / 蛋白质","${format(it)} kcal / ${format(summary.protein ?: 0.0)} g") }
        FeedbackRow("身体测量 / 完成训练","${summary.measurementDays} 天 / ${summary.completedWorkouts} 次")
        Text("只统计真实、非未来且数值有效的记录；有记录不代表记全，缺失日期不按零计算。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Text("下一步",style=MaterialTheme.typography.titleMedium)
        summary.actions.forEachIndexed { i,text -> Text("${i+1}. $text",style=MaterialTheme.typography.bodyMedium) }
        OutlinedButton(onClick=coach,modifier=Modifier.fillMaxWidth()) { Text("和教练制定下一周计划") }
    }
}
@Composable private fun FeedbackRow(title:String,value:String) { Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)) { Text(title,modifier=Modifier.weight(1f),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant); Text(value,style=MaterialTheme.typography.bodySmall) } }
private fun signed(value:Double)=(if(value>=0) "+" else "")+String.format(java.util.Locale.ROOT,"%.2f",value)

@Composable fun TrendChart(points:List<BodyTrend.Point>,unit:String,color:Color,smooth:Boolean=false,goal:Double?=null) {
    if(points.isEmpty()) return
    var selectedDay by rememberSaveable(points.map { it.day }.toString()) { mutableStateOf<String?>(null) }
    var width by remember { mutableIntStateOf(1) }
    val selected=points.firstOrNull { it.day.toString()==selectedDay } ?: points.last()
    val span=(points.last().day.toEpochDay()-points.first().day.toEpochDay()).coerceAtLeast(1)
    fun select(x:Float) { val day=points.first().day.toEpochDay()+x.coerceIn(0f,width.toFloat())/width*span; selectedDay=points.minBy { abs(it.day.toEpochDay()-day) }.day.toString() }
    val grid=MaterialTheme.colorScheme.surfaceVariant
    val values=points.map { if(smooth) it.trend else it.value }
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.Bottom) { Text("${format(if(smooth) selected.trend else selected.value)} $unit",style=MaterialTheme.typography.headlineMedium); Text(if(selectedDay==null) "最新" else "已选中",style=MaterialTheme.typography.labelSmall,color=color) }
    Canvas(Modifier.fillMaxWidth().height(180.dp).onSizeChanged { width=it.width.coerceAtLeast(1) }
        .semantics { contentDescription="横轴日期，纵轴$unit。点击或横向拖动查看数据；下方可逐条选择。" }
        .pointerInput(points) { detectTapGestures { select(it.x) } }
        .pointerInput(points) { detectHorizontalDragGestures(onDragStart={select(it.x)}) { change,_ -> change.consume();select(change.position.x) } }) {
        val low=values.min()-.3; val high=values.max()+.3
        fun x(day:LocalDate)=((day.toEpochDay()-points.first().day.toEpochDay()).toDouble()/span*(size.width-16.dp.toPx())+8.dp.toPx()).toFloat()
        fun y(v:Double)=(size.height*(1-(v-low)/(high-low))).toFloat()
        repeat(4) { val yy=size.height*it/3;drawLine(grid,Offset(0f,yy),Offset(size.width,yy),1.dp.toPx()) }
        if(goal!=null && goal in low..high) drawLine(color.copy(alpha=.4f),Offset(0f,y(goal)),Offset(size.width,y(goal)),1.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(8f,8f)))
        val path=Path();points.forEachIndexed { i,p -> if(i==0) path.moveTo(x(p.day),y(values[i])) else path.lineTo(x(p.day),y(values[i])) }
        val area=Path().apply { addPath(path);lineTo(x(points.last().day),size.height);lineTo(x(points.first().day),size.height);close() }
        drawPath(area,Brush.verticalGradient(listOf(color.copy(alpha=.18f),color.copy(alpha=.01f))))
        drawPath(path,color,style=Stroke(2.5.dp.toPx(),cap=StrokeCap.Round))
        points.forEachIndexed { i,p -> drawCircle(color,if(p.day==selected.day) 5.dp.toPx() else 2.5.dp.toPx(),Offset(x(p.day),y(values[i]))) }
        drawLine(color.copy(alpha=.35f),Offset(x(selected.day),0f),Offset(x(selected.day),size.height),1.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(6f,6f)))
    }
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) { Text(points.first().day.toString(),style=MaterialTheme.typography.labelSmall); Text(points.last().day.toString(),style=MaterialTheme.typography.labelSmall) }
    if(selectedDay!=null) Text("${selected.day} · 中位数 ${format(selected.value)} $unit · 趋势 ${format(selected.trend)} $unit · ${selected.count} 次测量",style=MaterialTheme.typography.bodySmall)
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
        val index=points.indexOf(selected)
        IconButton(enabled=index>0,onClick={selectedDay=points[index-1].day.toString()}) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft,"上一日测量") }
        Text(if(smooth) "每日中位数 · 指数平滑" else "每日中位数",modifier=Modifier.weight(1f),style=MaterialTheme.typography.bodySmall)
        IconButton(enabled=index<points.lastIndex,onClick={selectedDay=points[index+1].day.toString()}) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight,"下一日测量") }
    }
}

@Composable private fun MeasurementDetail(records:List<Record>,field:String,start:LocalDate,dismiss:()->Unit,detail:(Record)->Unit) {
    var period by rememberSaveable { mutableIntStateOf(0) }; var smooth by rememberSaveable { mutableStateOf(false) }
    val unit=if(field=="weight") "kg" else "%"
    val matching=records.filter { it.type==RecordType.BODY && !it.json.isNull(field) && (if(field=="weight") RecordQuality.validWeight(it) else it.json.optDouble(field) in 1.0..80.0) }.filter {
        val hour=Instant.ofEpochMilli((it.date*1000).toLong()).atZone(ZoneId.systemDefault()).hour
        when(period) { 1 -> hour in 5..11; 2 -> hour in 12..17; 3 -> hour in 18..23; 4 -> hour in 0..4; else -> true }
    }
    val points=BodyTrend.series(matching.map { BodyTrend.Sample(it.date,it.json.optDouble(field)) }).filter { it.day>=start }
    SubPage(if(field=="weight") "体重详情" else "体脂详情",dismiss) {
        Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(6.dp)) { listOf("全部","早上","下午","晚上","凌晨").forEachIndexed { i,label -> FilterChip(period==i,{period=i},label={Text(label)}) } }
        Text("早上 05–12 时 · 下午 12–18 时 · 晚上 18–24 时 · 凌晨 00–05 时",style=MaterialTheme.typography.bodySmall)
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) { Text("平滑趋势",modifier=Modifier.weight(1f));Switch(smooth,{smooth=it}) }
        Text("筛选时段后重新计算；缺测不补零。平滑趋势仅供观察长期变化。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        if(points.isEmpty()) Empty("此时段暂无测量","调整测量时段或添加记录") else Panel { TrendChart(points,unit,if(field=="weight") MaterialTheme.colorScheme.primary else Fat,smooth) }
        Text("原始测量",style=MaterialTheme.typography.titleMedium)
        matching.filter { it.date.day()>=start }.sortedByDescending { it.date }.forEach { r -> TextButton(onClick={detail(r)}) { Text("${r.date.localText()} · ${format(r.json.optDouble(field))} $unit") } }
    }
}

@Composable private fun RecordDataDetails(s:Snapshot,records:List<Record>,dismiss:()->Unit,detail:(Record)->Unit) {
    var search by rememberSaveable { mutableStateOf("") };var filter by rememberSaveable { mutableStateOf<RecordType?>(null) }
    SubPage("数据详情",dismiss) {
        Text("连续记录 ${Insights.streak(s.records)} 天 · 当前时段 ${records.map { it.date.day() }.distinct().size} 个记录日",style=MaterialTheme.typography.titleMedium)
        Text("全部记录",style=MaterialTheme.typography.titleLarge)
        OutlinedTextField(search,{search=it},Modifier.fillMaxWidth(),label={Text("搜索名称、备注与部位")},singleLine=true)
        Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(6.dp)) { FilterChip(filter==null,{filter=null},label={Text("全部")}); listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT).forEach { t -> FilterChip(filter==t,{filter=t},label={Text(t.label)}) } }
        val visible=records.filter { it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) && (filter==null || it.type==filter) && (search.isBlank() || it.title.contains(search,true) || it.json.optString("note").contains(search,true) || it.json.optJSONArray("exercises")?.objects()?.any { ex -> ex.optString("name").contains(search,true) || ex.optString("bodyPart").contains(search,true) }==true) }.sortedByDescending { it.date }
        if(visible.isEmpty()) Empty("没有符合条件的记录","调整范围或搜索内容")
        visible.forEach { r -> Panel { RecordRow(r) { detail(r) } } }
    }
}

@Composable fun BarChart(values:List<Double?>,goal:Double) {
    val color=MaterialTheme.colorScheme.primary; val empty=MaterialTheme.colorScheme.surfaceVariant
    Canvas(Modifier.fillMaxWidth().height(130.dp)) {
        val max=maxOf(goal,values.filterNotNull().maxOrNull() ?: goal,1.0)*1.15
        val width=size.width/values.size; val y=(size.height*(1-goal/max)).toFloat()
        drawLine(Meals,Offset(0f,y),Offset(size.width,y),1.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(8f,8f)))
        values.forEachIndexed { i,v -> val h=if(v==null) 3.dp.toPx() else (v/max*size.height).toFloat(); drawRoundRect(if(v==null) empty else color,Offset(i*width+width*.2f,size.height-h),androidx.compose.ui.geometry.Size(width*.6f,h),androidx.compose.ui.geometry.CornerRadius(4.dp.toPx())) }
    }
}
