@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
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
import androidx.compose.ui.semantics.*
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import kotlinx.coroutines.delay
import java.time.*
import kotlin.math.abs

@Composable fun Trends(vm: AppViewModel,s:Snapshot,detail:(Record)->Unit,coach:(String)->Unit,notify:(String)->Unit,edit:(Record)->Unit=detail) {
    var range by rememberSaveable { mutableIntStateOf(30) }
    var details by rememberSaveable { mutableStateOf(false) }
    var measurement by rememberSaveable { mutableStateOf<String?>(null) }
    var quality by rememberSaveable { mutableStateOf(false) }
    var showReport by rememberSaveable { mutableStateOf(false) }
    var showCalendar by rememberSaveable { mutableStateOf(false) }
    var workoutDetails by rememberSaveable {mutableStateOf(false)}
    var calorieDetails by rememberSaveable { mutableStateOf(false) }
    var at by remember { mutableDoubleStateOf(now()) }
    LaunchedEffect(Unit) { while(true) { delay(60_000); at=now() } }
    val acknowledged by vm.acknowledgedQuality.collectAsState()
    val report by vm.weeklyReport.collectAsState()
    val today=at.day(); val start=if(range==0) LocalDate.MIN else today.minusDays(range.toLong()-1)
    val real=s.records.filter { !it.demo && it.date<=at }
    val preview = real.none { it.type in listOf(RecordType.MEAL, RecordType.BODY, RecordType.WORKOUT) } && s.records.any { it.demo }
    val chartRecords = if(preview) s.records.filter { it.demo && it.date<=at } else real
    val records=chartRecords.filter { it.date.day()>=start }
    val meals=records.filter { it.type==RecordType.MEAL && RecordQuality.validNutrition(it) }
    val weights=BodyTrend.records(chartRecords,"weight",at,includeDemo=preview).filter { it.day>=start }
    val fat=BodyTrend.records(chartRecords,"bodyFat",at,includeDemo=preview).filter { it.day>=start }
    val workouts=records.filter { it.type==RecordType.WORKOUT }.sortedByDescending { it.date }
    val feedback=GoalFeedback.summarize(s.records,s.profile,range,at,acknowledged)
    val pending=RecordQuality.issues(s.records,at).filter { it.id !in acknowledged }
    val caloriePoints=meals.groupBy { it.date.day() }.map { (day,entries) -> DayBar(day,Insights.total(entries,"calories"),"当日餐食总量 · ${entries.size} 餐") }.sortedBy { it.day }
    val calorieStart=if(range==0) minOf(caloriePoints.firstOrNull()?.day ?: today,today.minusDays(6)) else start
    if(calorieDetails) { SubPage("每日热量",{calorieDetails=false}) {
        Panel(tint=Color(0xFFFF9500)) { DailyBarChart(caloriePoints,calorieStart,today,"kcal",color=Color(0xFFFF9500),goal=s.profile.optDouble("calorieGoal"),tag="calorie-detail-chart",calorieStyle=true) }
        Text("有记录的日期才计入；空白日期表示未记录。今日仍可能变化。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        meals.sortedByDescending { it.date }.forEach { r -> RecordRow(r) { detail(r) } }
    }; return }
    if(showCalendar) { WorkoutCalendarPage(chartRecords,{showCalendar=false},edit); return }
    if(workoutDetails) {WorkoutDetails(vm,workouts,{workoutDetails=false},edit,notify);return}
    if(details) { RecordDataDetails(s,chartRecords.filter { it.date.day()>=start },{details=false},detail); return }
    measurement?.let { field -> MeasurementDetail(chartRecords,field,start,{measurement=null},detail); return }
    if(quality) { QualityReview(vm,s,{quality=false},detail,notify); return }
    if(showReport) { SubPage("AI 周报",{showReport=false}) {
        report.generatedAt?.let { Text("生成于 ${it.localText()} · 最近七天",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        SelectionContainer { MarkdownText(report.text) }
        Text("这份报告使用生成时的记录快照；记录变化后可重新生成。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }; return }
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp,20.dp,16.dp,glassPageBottomPadding()),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item { PageTitle("趋势","回顾训练与身体变化") { SymbolButton(Glyph.List,"查看全部数据详情",{details=true}) } }
        if(preview) item { Panel { Text("示例预览",style=MaterialTheme.typography.titleMedium); Text("图表展示合成记录。添加真实记录后，趋势会自动展示你的数据；示例不计入目标反馈和周报。",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant) } }
        item { RangePicker(range) { range=it } }
        item { Panel(tint=Color(0xFF31B8C4)) {
            val teal=Color(0xFF31B8C4)
            Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                IconBadge(Glyph.Workout,teal)
                Text("训练节奏",Modifier.weight(1f),style=MaterialTheme.typography.titleLarge)
                IconButton(onClick={workoutDetails=true},modifier=Modifier.size(32.dp)) {AppIcon(Glyph.Chevron,teal,Modifier.size(15.dp),"查看训练详情")}
            }
            val complete=workouts.filter { !it.json.isNull("endDate") && it.json.optDouble("endDate") in it.date..at }
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.SpaceBetween) {
                Row(verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.spacedBy(4.dp)) {Text(format(complete.sumOf { (it.json.optDouble("endDate")-it.date)/60 }),style=MaterialTheme.typography.headlineMedium);Text("分钟",Modifier.padding(bottom=5.dp),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                Column(horizontalAlignment=Alignment.End) {Text("${complete.size} 次训练",style=MaterialTheme.typography.titleMedium);Text("${complete.map {it.date.day()}.distinct().size} 天有记录",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
            }
            if(complete.isEmpty()) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(17.dp)).background(teal.copy(alpha=.055f)).padding(14.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                Text("从一次训练开始",style=MaterialTheme.typography.titleMedium);Text("在今日页开始训练，结束后这里会留下你的节奏。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if(complete.isNotEmpty()) {
                val days=complete.groupBy { it.date.day() }.map { (day,entries) -> DayBar(day,entries.sumOf { (it.json.optDouble("endDate")-it.date)/60 },"${entries.size} 次训练") }.sortedBy { it.day }
                DailyBarChart(days,if(range==0) minOf(days.first().day,today.minusDays(6)) else start,today,"分钟",teal,headline=false,tag="workout-chart",emptyMessage="当天无已完成训练记录")
            }
            if(workouts.any { it.json.isNull("endDate") }) Text("有训练进行中，结束后计入统计",style=MaterialTheme.typography.bodySmall,color=teal)
            val byPart=workouts.flatMap {WorkoutParts.of(it)}.groupingBy {it}.eachCount()
            if(byPart.isNotEmpty()) Text(byPart.entries.sortedByDescending {it.value}.joinToString(" · ") {"${it.key} ${it.value} 次"},style=MaterialTheme.typography.bodySmall)
            HorizontalDivider(color=MaterialTheme.colorScheme.onSurface.copy(alpha=.08f))
            Row(Modifier.fillMaxWidth().clickable {showCalendar=true}.padding(vertical=4.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                AppIcon(Glyph.Calendar,teal,Modifier.size(24.dp))
                Column(Modifier.weight(1f)) {Text("训练日历",style=MaterialTheme.typography.titleMedium,color=teal);Text("按月查看训练量与训练内容",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                AppIcon(Glyph.Chevron,teal,Modifier.size(15.dp))
            }
            Row(Modifier.fillMaxWidth().clickable {workoutDetails=true}.heightIn(min=30.dp),verticalAlignment=Alignment.CenterVertically) {Text("训练内容与明细",Modifier.weight(1f),style=MaterialTheme.typography.bodyMedium.copy(fontWeight=FontWeight.SemiBold),color=teal);AppIcon(Glyph.Chevron,teal,Modifier.size(15.dp))}
        } }
        item { Panel {
            ChartHeading("体重趋势",Glyph.Weight,MaterialTheme.colorScheme.primary,"weight-detail") {measurement="weight"}
            if(weights.isEmpty()) Empty("等待第一次测量","记下体重，慢慢看见变化") else {
                TrendChart(weights,"kg",MaterialTheme.colorScheme.primary,goal=s.profile.optDouble("targetWeight"),inspectionControls=false)
                ChartFooter {measurement="weight"}
            }
        } }
        item { Panel(tint=Fat) {
            ChartHeading("体脂趋势",Glyph.Percent,Fat,"fat-detail") {measurement="bodyFat"}
            if(fat.isEmpty()) Empty("暂无体脂记录","测量后即可查看数值和变化") else {TrendChart(fat,"%",Fat,inspectionControls=false);ChartFooter {measurement="bodyFat"}}
        } }
        item { Panel(tint=Color(0xFFFF9500)) {
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                IconBadge(Glyph.Meal,Color(0xFFFF9500),36.dp)
                Spacer(Modifier.width(10.dp))
                Text("每日热量",Modifier.weight(1f),style=MaterialTheme.typography.titleLarge)
                IconButton(onClick={calorieDetails=true}) { AppIcon(Glyph.Chevron,MaterialTheme.colorScheme.primary,Modifier.size(15.dp),"查看每日热量详情") }
            }
            DailyBarChart(caloriePoints,calorieStart,today,"kcal",color=Color(0xFFFF9500),goal=s.profile.optDouble("calorieGoal"),tag="calorie-chart",calorieStyle=true)
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.SpaceBetween) {
                Text("每日合计",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick={calorieDetails=true},contentPadding=PaddingValues(0.dp)) {Text("查看详情",style=MaterialTheme.typography.bodySmall)}
            }
            Text("有记录的日期才计入；空白日期表示未记录。今日仍可能变化。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            val mealDays=meals.map { it.date.day() }.distinct().size
            Text("当前时段 · $mealDays 天记录饮食 · ${if(mealDays>0) format(Insights.total(meals,"calories")/mealDays) else "—"} kcal / 记录日",style=MaterialTheme.typography.bodyMedium)
        } }
        item { Panel {
            Text("AI 周报 · 近 7 天",style=MaterialTheme.typography.titleLarge)
            if(report.text.isNotEmpty()) {
                report.generatedAt?.let { Text("生成于 ${it.localText()}",style=MaterialTheme.typography.bodySmall) }
                SoftButton(onClick={showReport=true},modifier=Modifier.fillMaxWidth()) { Text("阅读本周报告") }
            }
            if(report.error.isNotBlank()) Text(report.error,color=MaterialTheme.colorScheme.error)
            AppButton(onClick={vm.generateWeeklyReport()},enabled=!report.generating && real.any { it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) },modifier=Modifier.fillMaxWidth()) {
                if(report.generating) CircularProgressIndicator(Modifier.size(18.dp),strokeWidth=2.dp)
                Spacer(Modifier.width(8.dp)); Text(if(report.generating) "正在整理这一周…" else if(report.text.isEmpty()) "生成本周报告" else "重新生成")
            }
            if(real.isEmpty()) Text("先添加真实记录，示例不参与周报。",style=MaterialTheme.typography.bodySmall)
        } }
        item { FeedbackCard(feedback,s.profile) { coach("请依据以下截至今天的历史记录，回顾这段时间的身体、饮食和训练变化。先说明记录不足，再给出简短解读，不把体重变化当成脂肪或肌肉变化，不自动调整目标。\n${feedback.context}") } }
        item { Panel(Modifier.clickable { quality=true }) {
            Text("记录质量检查",style=MaterialTheme.typography.titleLarge)
            Text(if(pending.isEmpty()) "暂无待核对项 · 检查全部真实记录" else "${pending.size} 项待核对 · 查看疑点并修正",color=MaterialTheme.colorScheme.onSurfaceVariant)
        } }
    }

}

@Composable private fun FeedbackCard(summary:GoalFeedback.Summary,goals:org.json.JSONObject,coach:()->Unit) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val dateFormat=java.time.format.DateTimeFormatter.ofPattern("M/d")
    Panel {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) {
            IconBadge(Glyph.Target,MaterialTheme.colorScheme.primary)
            Text("目标反馈",Modifier.weight(1f),style=MaterialTheme.typography.titleMedium)
            Text("${summary.start.format(dateFormat)}—${summary.end.format(dateFormat)}",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.spacedBy(6.dp)) {
            Text(summary.latest?.trend?.let(::format) ?: "—",style=MaterialTheme.typography.headlineLarge)
            Text("kg",Modifier.padding(bottom=5.dp),color=MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
            Text("趋势体重",Modifier.padding(bottom=5.dp),style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(summary.headline,style=MaterialTheme.typography.bodyMedium.copy(fontWeight=FontWeight.Medium))
        summary.period?.let { period ->
            Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {
                    Text("阶段变化 ${signed(period.change)} kg",style=MaterialTheme.typography.bodySmall)
                    Text("参考 ${signed(period.targetChange)} kg",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
                LinearProgressIndicator(progress={period.fraction.toFloat()},modifier=Modifier.fillMaxWidth().semantics { contentDescription="所选历史时段的体重变化相对于阶段目标" })
            }
        }
        Row(horizontalArrangement=Arrangement.spacedBy(10.dp)) {
            listOf(Triple("饮食记录",summary.mealDays,"天"),Triple("身体测量",summary.measurementDays,"天"),Triple("完成训练",summary.completedWorkouts,"次")).forEach { (title,value,unit) ->
                Column(Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.primary.copy(alpha=.05f)).padding(12.dp),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                    Text(title,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("$value $unit",style=MaterialTheme.typography.titleMedium)
                }
            }
        }
        TextButton(onClick={expanded=!expanded},contentPadding=PaddingValues(0.dp),modifier=Modifier.testTag("feedback-details")) {
            Text(if(expanded) "收起记录与解读" else "记录与解读")
        }
        if(expanded) {
            summary.latest?.let { FeedbackRow("最近测量",it.day.format(dateFormat)) }
            summary.distance?.let { FeedbackRow("距目标体重","${format(it)} kg") }
            summary.period?.let { period -> Text("比较 ${period.baseline.format(dateFormat)} 至最近测量的趋势体重；参考值按每周目标和实际测量跨度换算。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
            summary.weeklyChange?.let { FeedbackRow("平均每周变化","${signed(it)} kg") }
            FeedbackRow("热量在目标 ±10% 内",if(goals.optDouble("calorieGoal")>0) "${summary.calorieDays} / ${summary.mealDays} 个记录日" else "请核对目标")
            FeedbackRow("蛋白质达到目标",if(goals.optDouble("proteinGoal")>0) "${summary.proteinDays} / ${summary.mealDays} 个记录日" else "请核对目标")
            summary.calories?.let { FeedbackRow("记录日均热量","${format(it)} kcal") }
            summary.protein?.let { FeedbackRow("记录日均蛋白质","${format(it)} g") }
            Text("仅统计真实有效记录，缺失日期不按零计算。体重变化不等同于增肌或减脂成果。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            HorizontalDivider()
            summary.actions.forEach { Text(it,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        SoftButton(onClick=coach,modifier=Modifier.fillMaxWidth()) { Text("和教练复盘") }
    }
}
@Composable private fun FeedbackRow(title:String,value:String) { Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)) { Text(title,modifier=Modifier.weight(1f),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant); Text(value,style=MaterialTheme.typography.bodySmall) } }
internal fun signed(value:Double)=(if(value>=0) "+" else "")+String.format(java.util.Locale.ROOT,"%.2f",value)

@Composable private fun ChartHeading(title:String,kind:Glyph,color:Color,tag:String,open:()->Unit) {
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) {
        IconBadge(kind,color,36.dp);Text(title,Modifier.weight(1f),style=MaterialTheme.typography.titleLarge)
        IconButton(onClick=open,modifier=Modifier.testTag(tag).size(44.dp)) {AppIcon(Glyph.Chevron,color,Modifier.size(15.dp),"${title}详情")}
    }
}
@Composable private fun ChartFooter(open:()->Unit) {
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.SpaceBetween) {
        Text("每日中位数",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        TextButton(onClick=open,contentPadding=PaddingValues(0.dp)) {Text("查看详情",style=MaterialTheme.typography.bodySmall)}
    }
}
@Composable fun TrendChart(points:List<BodyTrend.Point>,unit:String,color:Color,smooth:Boolean=false,goal:Double?=null,inspectionControls:Boolean=true,dualSeries:Boolean=false) {
    if(points.isEmpty()) return
    var selectedDay by rememberSaveable(points.map {it.day}.toString()) {mutableStateOf<String?>(null)}
    var width by remember {mutableIntStateOf(1)}
    val density=LocalDensity.current
    val labelColor=MaterialTheme.colorScheme.onSurfaceVariant
    val grid=MaterialTheme.colorScheme.onSurface.copy(alpha=.075f)
    val labels=remember(labelColor,density) {android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {this.color=labelColor.toArgb();textSize=with(density) {10.sp.toPx()}}}
    val selected=points.firstOrNull {it.day.toString()==selectedDay} ?: points.last()
    val first=points.first().day.toEpochDay()-.5
    val span=(points.last().day.toEpochDay()-points.first().day.toEpochDay()+1).coerceAtLeast(1).toDouble()
    val values=points.map {if(smooth) it.trend else it.value}
    val domainValues=if(dualSeries) points.flatMap {listOf(it.value,it.trend)} else values
    val pad=maxOf((domainValues.max()-domainValues.min())*.25,.8)
    val low=domainValues.min()-pad;val high=domainValues.max()+pad
    val axisWidth=maxOf(with(density) {32.dp.toPx()},maxOf(labels.measureText(String.format(java.util.Locale.ROOT,"%.1f",low)),labels.measureText(String.format(java.util.Locale.ROOT,"%.1f",high)))+with(density) {8.dp.toPx()})
    fun select(x:Float) {val day=first+((x-axisWidth)/(width-axisWidth-8f).coerceAtLeast(1f)).coerceIn(0f,1f)*span;selectedDay=points.minBy {abs(it.day.toEpochDay()-day)}.day.toString()}
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.spacedBy(4.dp)) {
        Text(String.format(java.util.Locale.ROOT,"%.1f",if(smooth) selected.trend else selected.value),style=MaterialTheme.typography.headlineMedium)
        Text(unit,Modifier.padding(bottom=5.dp),style=MaterialTheme.typography.bodyLarge,color=labelColor)
        Spacer(Modifier.weight(1f));Text(if(selectedDay==null) "最新" else "已选中",style=MaterialTheme.typography.labelSmall,color=color)
    }
    Canvas(Modifier.fillMaxWidth().height(210.dp).onSizeChanged {width=it.width.coerceAtLeast(1)}
        .semantics {
            contentDescription=if(dualSeries) "体重走势，虚线为每日中位数，实线为趋势体重" else "横轴日期，纵轴$unit。点击或横向拖动查看数据。"
            stateDescription="${selected.day}，中位数 ${format(selected.value)} $unit，趋势 ${format(selected.trend)} $unit，${selected.count} 次测量"
            customActions=listOf(
                CustomAccessibilityAction("上一日测量") { val i=points.indexOf(selected);if(i>0) {selectedDay=points[i-1].day.toString();true} else false },
                CustomAccessibilityAction("下一日测量") { val i=points.indexOf(selected);if(i<points.lastIndex) {selectedDay=points[i+1].day.toString();true} else false }
            )
        }
        .pointerInput(points) {detectTapGestures {select(it.x)}}
        .pointerInput(points) {detectHorizontalDragGestures(onDragStart={select(it.x)}) {change,_ -> change.consume();select(change.position.x)}}) {
        val left=axisWidth;val right=size.width-8.dp.toPx();val top=6.dp.toPx();val bottom=size.height-24.dp.toPx()
        fun x(day:LocalDate)=(left+(day.toEpochDay()-first)/span*(right-left)).toFloat()
        fun y(v:Double)=(top+(bottom-top)*(1-(v-low)/(high-low))).toFloat()
        repeat(4) {i ->
            val yy=top+(bottom-top)*i/3
            drawLine(grid,Offset(left,yy),Offset(right,yy),.7.dp.toPx())
            drawIntoCanvas {canvas -> val label=String.format(java.util.Locale.ROOT,"%.1f",high-(high-low)*i/3);canvas.nativeCanvas.drawText(label,left-5.dp.toPx()-labels.measureText(label),yy+labels.textSize*.35f,labels)}
            val xx=left+(right-left)*i/3
            drawLine(grid,Offset(xx,top),Offset(xx,bottom),.7.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(),3.dp.toPx())))
            val date=LocalDate.ofEpochDay((first+span*i/3).toLong()).format(java.time.format.DateTimeFormatter.ofPattern("M/d"))
            drawIntoCanvas {it.nativeCanvas.drawText(date,xx-labels.measureText(date)/2,size.height-4.dp.toPx(),labels)}
        }
        if(goal!=null && goal in low..high) drawLine(color.copy(alpha=.4f),Offset(left,y(goal)),Offset(right,y(goal)),1.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(8f,8f)))
        val path=Path();points.forEachIndexed {i,p -> if(i==0) path.moveTo(x(p.day),y(values[i])) else path.lineTo(x(p.day),y(values[i]))}
        val area=Path().apply {addPath(path);lineTo(x(points.last().day),bottom);lineTo(x(points.first().day),bottom);close()}
        drawPath(area,Brush.verticalGradient(listOf(color.copy(alpha=.18f),color.copy(alpha=.01f))))
        if(dualSeries) {
            val raw=Path()
            points.forEachIndexed {i,p -> if(i==0) raw.moveTo(x(p.day),y(p.value)) else raw.lineTo(x(p.day),y(p.value)) }
            drawPath(raw,labelColor,style=Stroke(1.5.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(),4.dp.toPx()))))
            points.forEach {p -> drawCircle(labelColor,2.dp.toPx(),Offset(x(p.day),y(p.value))) }
        }
        drawPath(path,color,style=Stroke(2.5.dp.toPx(),cap=StrokeCap.Round))
        points.forEachIndexed {i,p -> drawCircle(color,if(p.day==selected.day) 4.dp.toPx() else 2.5.dp.toPx(),Offset(x(p.day),y(values[i])))}
        if(selectedDay!=null) drawLine(color.copy(alpha=.35f),Offset(x(selected.day),top),Offset(x(selected.day),bottom),1.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(6f,6f)))
    }
    if(dualSeries) {
        FlowRow(horizontalArrangement=Arrangement.spacedBy(16.dp),verticalArrangement=Arrangement.spacedBy(6.dp)) {
            Text("虚线 · 每日中位数",style=MaterialTheme.typography.bodySmall,color=labelColor)
            Text("实线 · 趋势体重",style=MaterialTheme.typography.bodySmall,color=color)
        }
    }
    if(selectedDay!=null) Text("${selected.day} · 中位数 ${format(selected.value)} $unit · 趋势 ${format(selected.trend)} $unit · ${selected.count} 次测量",style=MaterialTheme.typography.bodySmall)
    if(inspectionControls) Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
        val index=points.indexOf(selected)
        IconButton(enabled=index>0,onClick={selectedDay=points[index-1].day.toString()}) {Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft,"上一日测量")}
        Text(if(smooth) "每日中位数 · 指数平滑" else "每日中位数",modifier=Modifier.weight(1f),style=MaterialTheme.typography.bodySmall)
        IconButton(enabled=index<points.lastIndex,onClick={selectedDay=points[index+1].day.toString()}) {Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight,"下一日测量")}
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
    LazySubPage(if(field=="weight") "体重详情" else "体脂详情",dismiss) {
        item { ChoiceControl(listOf("全部","早上","下午","晚上","凌晨").mapIndexed {i,label -> i.toString() to label},period.toString(),{period=it.toInt()}) }
        item { Text("早上 05–12 时 · 下午 12–18 时 · 晚上 18–24 时 · 凌晨 00–05 时",style=MaterialTheme.typography.bodySmall) }
        item { Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) { Text("平滑趋势",modifier=Modifier.weight(1f));Switch(smooth,{smooth=it}) } }
        item { Text("筛选时段后重新计算；缺测不补零。平滑趋势仅供观察长期变化。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        item { if(points.isEmpty()) Empty("此时段暂无测量","调整测量时段或添加记录") else Panel { TrendChart(points,unit,if(field=="weight") MaterialTheme.colorScheme.primary else Fat,smooth) } }
        item { Text("原始测量",style=MaterialTheme.typography.titleMedium) }
        items(matching.filter { it.date.day()>=start }.sortedByDescending { it.date },key={it.id}) { r -> TextButton(onClick={detail(r)}) { Text("${r.date.localText()} · ${format(r.json.optDouble(field))} $unit") } }
    }
}

@Composable private fun RecordDataDetails(s:Snapshot,records:List<Record>,dismiss:()->Unit,detail:(Record)->Unit) {
    var search by rememberSaveable { mutableStateOf("") };var filter by rememberSaveable { mutableStateOf<RecordType?>(null) }
    var bodyOverview by rememberSaveable { mutableStateOf(false) }
    var selectedDayText by rememberSaveable { mutableStateOf<String?>(null) }
    val selectedDay=selectedDayText?.let(LocalDate::parse)
    val preview=records.any {it.demo} && s.records.none {!it.demo && it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT)}
    if(bodyOverview) {BodyOverviewPage(s.records,{bodyOverview=false},detail);return}
    LazySubPage("数据详情",dismiss) {
        item("overview") { Column(verticalArrangement=Arrangement.spacedBy(16.dp)) { RecordOverview(s,records,selectedDay,{selectedDayText=it?.toString()},{bodyOverview=true}) } }
        item { Text("连续记录 ${Insights.streak(s.records)} 天 · 当前时段 ${records.map { it.date.day() }.distinct().size} 个记录日",style=MaterialTheme.typography.titleMedium) }
        item { Text("全部记录",style=MaterialTheme.typography.titleLarge) }
        item { OutlinedTextField(search,{search=it},Modifier.fillMaxWidth(),label={Text("搜索名称、备注与部位")},singleLine=true) }
        item { ChoiceControl(listOf("" to "全部")+listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT).map {it.name to it.label},filter?.name.orEmpty(),{filter=it.takeIf {value -> value.isNotEmpty()}?.let(RecordType::valueOf)}) }
        val visible=(if(selectedDay==null) records else s.records.filter {(preview || !it.demo) && it.date<=now()}).filter { it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) && (filter==null || it.type==filter) && (selectedDay==null || it.date.day()==selectedDay) && (search.isBlank() || it.title.contains(search,true) || it.json.optString("note").contains(search,true) || it.json.optJSONArray("exercises")?.objects()?.any { ex -> ex.optString("name").contains(search,true) || ex.optString("bodyPart").contains(search,true) }==true) }.sortedByDescending { it.date }
        if(visible.isEmpty()) item("empty") { Empty("没有符合条件的记录","调整范围或搜索内容") }
        items(visible,key={"${it.type}:${it.id}"}) { r -> Panel { RecordRow(r) { detail(r) } } }
    }
}
