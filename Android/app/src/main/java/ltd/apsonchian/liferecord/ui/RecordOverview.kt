package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.data.*
import java.time.LocalDate

@Composable fun RecordOverview(s:Snapshot,records:List<Record>,selectedDay:LocalDate?,select:(LocalDate?)->Unit,body:()->Unit) {
    Panel(Modifier.clickable(onClick=body)) {
        Text("身体总览",style=MaterialTheme.typography.titleMedium)
        Text("趋势体重 · 今日基准 · 身体组成",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
    val today=LocalDate.now();val first=today.minusDays(29)
    val visible=s.records.filter {!it.demo && it.date<=now() && it.type in listOf(RecordType.MEAL,RecordType.BODY)}
    Panel {
        Text("记录日历 · 近 30 天",style=MaterialTheme.typography.titleMedium)
        Text("${first} — $today",style=MaterialTheme.typography.bodySmall)
        Row(Modifier.fillMaxWidth()) {listOf("一","二","三","四","五","六","日").forEach {Text(it,Modifier.weight(1f).wrapContentWidth(Alignment.CenterHorizontally),style=MaterialTheme.typography.bodySmall)} }
        val gridStart=first.minusDays((first.dayOfWeek.value-1).toLong())
        val total=java.time.temporal.ChronoUnit.DAYS.between(gridStart,today).toInt()+1
        (0 until (total+6)/7).forEach { week ->
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(4.dp)) {
                (0..6).forEach { column ->
                    val day=gridStart.plusDays((week*7+column).toLong());val valid=day in first..today
                    val count=visible.filter {it.date.day()==day}.map {it.type}.distinct().size
                    Box(Modifier.weight(1f).heightIn(min=44.dp).clip(RoundedCornerShape(10.dp))
                        .background(MaterialTheme.colorScheme.primary.copy(alpha=if(day==selectedDay) .35f else if(count>0) .08f+count*.08f else .025f))
                        .clickable(enabled=valid) {select(day)}.semantics {contentDescription="$day，$count 类记录"},contentAlignment=Alignment.Center) {
                        Text(if(valid) day.dayOfMonth.toString() else "",style=MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
        Text("颜色表示饮食和身体测量的记录类别数；空白不表示未达标。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        selectedDay?.let { TextButton(onClick={select(null)}) {Text("$it · 查看当前范围全部记录")} }
    }
    val meals=records.filter {it.type==RecordType.MEAL && !it.demo && it.date<=now() && RecordQuality.validNutrition(it)}
    val days=meals.map {it.date.day()}.distinct().size
    Panel {
        Text("宏量营养均值",style=MaterialTheme.typography.titleMedium)
        listOf("protein" to "蛋白质","carbs" to "碳水","fat" to "脂肪","fiber" to "膳食纤维").forEach { (key,label) ->
            OverviewValue(label,if(days>0) "${format(Insights.total(meals,key)/days)} g" else "—")
        }
        Text("按当前范围 $days 个饮食记录日计算，未记录日期不按零计算。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
