package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ltd.apsonchian.liferecord.data.DayChartAxis
import ltd.apsonchian.liferecord.data.format
import java.time.LocalDate

data class DayBar(val day: LocalDate, val value: Double, val note: String = "")

@Composable fun DailyBarChart(
    points: List<DayBar>, start: LocalDate, end: LocalDate, unit: String,
    color: Color = MaterialTheme.colorScheme.primary, goal: Double? = null,
    headline: Boolean = true, tag: String = "daily-bar-chart",
    emptyMessage: String = "当天未记录，不按零计算。",
    calorieStyle: Boolean = false
) {
    val axis = remember(start, end) { DayChartAxis(start, end) }
    var selectedText by rememberSaveable(start.toString(), end.toString()) { mutableStateOf<String?>(null) }
    val selectedDay = selectedText?.let(LocalDate::parse) ?: points.maxByOrNull { it.day }?.day ?: end
    val selected = points.firstOrNull { it.day == selectedDay }
    val textColor = MaterialTheme.colorScheme.onSurfaceVariant
    val gridColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .10f)
    var canvasWidth by remember { mutableIntStateOf(0) }
    val density = androidx.compose.ui.platform.LocalDensity.current
    fun display(value: Double) = if(calorieStyle) String.format(java.util.Locale.ROOT,"%,.0f",value) else format(value)
    val left = with(density) { 42.dp.toPx() }
    val right = with(density) { 8.dp.toPx() }
    fun inspect(x: Float) {
        val width = canvasWidth - left - right
        if(width > 0 && x in left..(canvasWidth - right)) selectedText = axis.dayAt((x-left)/width).toString()
    }
    if(headline) Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Text(selected?.value?.let(::display) ?: "—", style = if(calorieStyle) MaterialTheme.typography.headlineLarge else MaterialTheme.typography.headlineMedium)
        Text(unit, Modifier.padding(start=6.dp, bottom=4.dp), color=textColor)
        Spacer(Modifier.weight(1f))
        Text(if(selectedText == null) "最新" else "已选中", style=MaterialTheme.typography.bodySmall, color=color)
    }
    Canvas(Modifier.fillMaxWidth().height(if(calorieStyle) 210.dp else 178.dp).testTag(tag)
        .onSizeChanged { canvasWidth = it.width }
        .semantics { contentDescription = "横轴日期 ${axis.first} 至 ${axis.last}，纵轴 $unit。$selectedDay：${selected?.let { "${format(it.value)} $unit" } ?: emptyMessage}" }
        .pointerInput(axis, canvasWidth, points) { detectTapGestures { inspect(it.x) } }
        .pointerInput(axis, canvasWidth, points) { detectHorizontalDragGestures { change, _ -> inspect(change.position.x); change.consume() } }
    ) {
        val top=8.dp.toPx(); val bottom=size.height-28.dp.toPx(); val width=size.width-left-right
        val ticks=DayChartAxis.valueTicks(points.filter {it.value.isFinite()}.maxOfOrNull {it.value} ?: 0.0,goal)
        val maximum=ticks.last()
        fun x(day:LocalDate)=left+axis.fraction(day)*width
        fun y(value:Double)=bottom-((value/maximum).coerceIn(0.0,1.0)*(bottom-top)).toFloat()
        val paint=android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { this.color=textColor.toArgb();textSize=11.sp.toPx() }
        drawContext.canvas.nativeCanvas.apply {
            ticks.forEach { value ->
                drawLine(gridColor,Offset(left,y(value)),Offset(size.width-right,y(value)),1.dp.toPx())
                drawText(display(value),0f,y(value)+4.dp.toPx(),paint)
            }
            axis.ticks().forEach { day ->
                if(calorieStyle) drawLine(gridColor,Offset(x(day),top),Offset(x(day),bottom),1.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(4f,4f)))
                val label=axis.label(day); val textWidth=paint.measureText(label)
                drawText(label,(x(day)-textWidth/2).coerceIn(left,(size.width-right-textWidth).coerceAtLeast(left)),size.height-5.dp.toPx(),paint)
            }
        }
        goal?.takeIf { it.isFinite() && it > 0 }?.let {
            drawLine(if(calorieStyle) Protein.copy(alpha=.3f) else color.copy(alpha=.45f),Offset(left,y(it)),Offset(size.width-right,y(it)),1.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(8f,8f)))
        }
        points.filter { it.day in axis.first..axis.last && it.value.isFinite() && it.value >= 0 }.forEach { point ->
            val barWidth=minOf(14.dp.toPx(),width/axis.count*.64f).coerceAtLeast(1f)
            val height=(bottom-y(point.value)).coerceAtLeast(1.5.dp.toPx())
            val alpha=if(calorieStyle) { if(point.day==selectedDay) 1f else .4f } else if(selectedText==null || point.day==selectedDay) 1f else .35f
            drawRoundRect(color.copy(alpha=alpha),Offset(x(point.day)-barWidth/2,bottom-height),Size(barWidth,height),androidx.compose.ui.geometry.CornerRadius(4.dp.toPx()))
        }
        if(selectedText != null || calorieStyle && selected != null) drawLine(color.copy(alpha=.35f),Offset(x(selectedDay),top),Offset(x(selectedDay),bottom),1.dp.toPx(),pathEffect=PathEffect.dashPathEffect(floatArrayOf(5f,5f)))
    }
    if(calorieStyle) {
        if(selectedText != null) Column(verticalArrangement=Arrangement.spacedBy(4.dp)) {
            Text("${axis.label(selectedDay)} · ${selected?.let { "${display(it.value)} $unit" } ?: "未记录"}",style=MaterialTheme.typography.bodySmall)
            Text(selected?.note?.ifBlank { "每日合计" } ?: emptyMessage,style=MaterialTheme.typography.bodySmall,color=textColor)
            TextButton(onClick={selectedText=null},contentPadding=PaddingValues(0.dp)) {Text("收起详情")}
        }
    } else Row(Modifier.fillMaxWidth(), verticalAlignment=Alignment.CenterVertically) {
        IconButton(enabled=selectedDay>axis.first,onClick={selectedText=selectedDay.minusDays(1).toString()}) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft,"上一日") }
        Column(Modifier.weight(1f)) {
            Text("${axis.label(selectedDay)} · ${selected?.let { "${format(it.value)} $unit" } ?: "未记录"}",style=MaterialTheme.typography.bodySmall)
            Text(selected?.note?.ifBlank { "每日合计" } ?: emptyMessage,style=MaterialTheme.typography.bodySmall,color=textColor)
        }
        IconButton(enabled=selectedDay<axis.last,onClick={selectedText=selectedDay.plusDays(1).toString()}) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight,"下一日") }
    }
}
