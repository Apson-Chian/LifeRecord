@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.data.*
import java.time.*
import kotlinx.coroutines.delay

@Composable fun WorkoutCalendarPage(records: List<Record>, dismiss: () -> Unit, edit: (Record) -> Unit) {
    var monthText by rememberSaveable { mutableStateOf(YearMonth.now().toString()) }
    var selectedText by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var showDay by rememberSaveable { mutableStateOf(false) }
    var at by remember { mutableDoubleStateOf(now()) }
    LaunchedEffect(Unit) { while(true) { delay(60_000); at=now() } }
    val month=YearMonth.parse(monthText); val selected=LocalDate.parse(selectedText)
    val calendar=WorkoutCalendar.month(month,records,at); val green=Color(0xFF29AD5E)
    SubPage("训练日历",dismiss) {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(4.dp)) {
            SymbolButton(Glyph.Chevron,"上个月",{monthText=month.minusMonths(1).toString();selectedText=YearMonth.parse(monthText).atDay(1).toString()},Modifier.rotate(180f))
            Column { Text(month.year.toString(),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant);Text("${month.monthValue}月",style=MaterialTheme.typography.headlineMedium,modifier=Modifier.testTag("workout-month")) }
            SymbolButton(Glyph.Chevron,"下个月",{monthText=month.plusMonths(1).toString();selectedText=YearMonth.parse(monthText).atDay(1).toString()})
            Spacer(Modifier.weight(1f))
            SoftButton(onClick={at=now();monthText=YearMonth.now().toString();selectedText=LocalDate.now().toString()}) { Text("回到本月",style=MaterialTheme.typography.bodySmall) }
        }
        Text("本月 ${calendar.recordedDays} 天 · ${calendar.completedCount} 次训练 · ${format(calendar.minutes)} 分钟",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Column(verticalArrangement=Arrangement.spacedBy(8.dp),modifier=Modifier.testTag("workout-calendar")) {
            Row { listOf("一","二","三","四","五","六","日").forEach {Text(it,Modifier.weight(1f),textAlign=androidx.compose.ui.text.style.TextAlign.Center,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)} }
            HorizontalDivider()
            calendar.days.chunked(7).forEach { week -> Row(horizontalArrangement=Arrangement.spacedBy(4.dp)) {
                week.forEach {day ->
                    val today=day.date==at.day()
                    Column(Modifier.weight(1f).heightIn(min=96.dp).clip(RoundedCornerShape(8.dp)).background(if(day.date==selected) green.copy(alpha=.08f) else Color.Transparent)
                        .border(1.dp,if(day.date==selected) green else Color.Transparent,RoundedCornerShape(8.dp)).alpha(if(day.inMonth) 1f else .35f)
                        .clickable {selectedText=day.date.toString();if(!day.inMonth) monthText=YearMonth.from(day.date).toString();showDay=true}
                        .testTag("workout-day-${day.date}").semantics(mergeDescendants=true) { contentDescription="${day.date}，${day.sessions.size} 条训练，已完成 ${day.completed.size} 次"+(day.volume?.let {"，记录训练量 ${format(it)} 千克次"} ?: ""); stateDescription=if(day.date==selected) "已选择" else "" }
                        .padding(horizontal=2.dp,vertical=4.dp),verticalArrangement=Arrangement.spacedBy(4.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                        Box(Modifier.size(28.dp).background(if(today) green else Color.Transparent,CircleShape),contentAlignment=Alignment.Center) {Text(day.date.dayOfMonth.toString(),style=MaterialTheme.typography.bodyMedium,fontWeight=if(today) FontWeight.Bold else FontWeight.Normal,color=if(today) Color.White else MaterialTheme.colorScheme.onSurface)}
                        if(day.completed.isNotEmpty()) Text(day.volume?.let(::format) ?: "已训练",Modifier.fillMaxWidth().background(green.copy(alpha=.8f),RoundedCornerShape(3.dp)).padding(vertical=2.dp),style=MaterialTheme.typography.labelSmall,fontWeight=FontWeight.Bold,color=Color.Black,textAlign=androidx.compose.ui.text.style.TextAlign.Center,maxLines=1,overflow=TextOverflow.Ellipsis)
                        else if(day.sessions.isNotEmpty()) Text(if(day.sessions.any {it.json.isNull("endDate") && it.date<=at}) "进行中" else "待完成",Modifier.fillMaxWidth().background(Carbs.copy(alpha=.12f),RoundedCornerShape(3.dp)),style=MaterialTheme.typography.labelSmall,color=Carbs,maxLines=1)
                        day.sessions.take(2).forEach { Text(WorkoutCalendar.title(it),Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.onSurface.copy(alpha=.06f),RoundedCornerShape(3.dp)).padding(2.dp),style=MaterialTheme.typography.labelSmall,maxLines=2,overflow=TextOverflow.Ellipsis) }
                        if(day.sessions.size>2) Text("+${day.sessions.size-2} 条",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            } }
        }
        Text("绿色数字：记录训练量（kg·次）",style=MaterialTheme.typography.bodySmall,color=green)
        Text("按已填写的负重 × 次数累加；未填写数值不估算。点击日期查看完整内容，跨午夜训练归入开始日。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if(showDay) GlassBottomSheet(onDismissRequest={showDay=false}) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp).navigationBarsPadding(),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {Text("当天训练",Modifier.weight(1f),style=MaterialTheme.typography.titleLarge);TextButton(onClick={showDay=false}) {Text("完成")}}
            Text(selected.toString(),style=MaterialTheme.typography.titleMedium)
            val entries=records.filter {it.type==RecordType.WORKOUT && it.date.day()==selected}.sortedBy {it.date}
            if(entries.isEmpty()) Text("当天没有训练记录",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
            entries.forEach {r -> Panel(Modifier.clickable {edit(r)},tint=green) {
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {Text(r.date.localText(),style=MaterialTheme.typography.titleMedium);AppIcon(Glyph.Compose,green,Modifier.size(18.dp),"编辑训练")}
                Text(WorkoutCalendar.content(r),style=MaterialTheme.typography.bodyMedium)
                if(WorkoutCalendar.completed(r,at)) Text("${format((r.json.getDouble("endDate")-r.date)/60)} 分钟"+(WorkoutCalendar.volume(r)?.let {" · ${format(it)} kg·次"} ?: ""),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                else Text(if(r.json.isNull("endDate") && r.date<=at) "训练进行中，结束后计入统计" else "尚未计入已完成训练",style=MaterialTheme.typography.bodySmall,color=Carbs)
            } }
        }
    }
}
