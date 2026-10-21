package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.data.*
import java.time.LocalDate

@Composable fun BodyOverviewPage(records:List<Record>,dismiss:()->Unit,detail:(Record)->Unit) {
    val preview=records.any {it.demo} && records.none {!it.demo && it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT)}
    val summary=remember(records,preview) { BodyOverview.summarize(records,includeDemo=preview) }
    var history by rememberSaveable { mutableStateOf(false) }
    val measurements=records.filter {it.type==RecordType.BODY && (preview || !it.demo) && it.date<=now()}.sortedByDescending {it.date}
    val today=measurements.filter {it.date.day()==LocalDate.now()}
    LazySubPage("身体总览",dismiss) {
        if(preview) item { Text("示例预览 · 合成身体测量",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.primary) }
        item { Panel {
            Text("趋势体重",style=MaterialTheme.typography.titleMedium)
            Text(summary.points.lastOrNull()?.trend?.let {"${format(it)} kg"} ?: "—",style=MaterialTheme.typography.headlineLarge)
            OverviewValue("今日中位数",summary.today?.value?.let {"${format(it)} kg"} ?: "—")
            OverviewValue("今日测量",summary.today?.count?.let {"$it 次"} ?: "—")
            OverviewValue("近 7 天变化",summary.change7?.let {"${signed(it)} kg"} ?: "记录不足")
            OverviewValue("近 30 天变化",summary.change30?.let {"${signed(it)} kg"} ?: "记录不足")
            OverviewValue("趋势变化速度",summary.weeklyRate?.let {"${signed(it)} kg/周"} ?: "记录不足")
        } }
        item { Panel {
            Text("每日中位数与趋势",style=MaterialTheme.typography.titleMedium)
            if(summary.points.isEmpty()) Empty("暂无测量","记录体重后查看变化") else TrendChart(summary.points,"kg",MaterialTheme.colorScheme.primary,true,dualSeries=true)
        } }
        item { Panel(tint=Fat) {
            Text("身体组成",style=MaterialTheme.typography.titleMedium)
            OverviewValue("体脂率",summary.composition?.json?.getDouble("bodyFat")?.let {"${format(it)}%"} ?: "—")
            OverviewValue("脂肪量",summary.fatMass?.let {"${format(it)} kg"} ?: "—")
            OverviewValue("瘦体重",summary.leanMass?.let {"${format(it)} kg"} ?: "—")
            Text(summary.composition?.let {"依据 ${it.date.localText()} 同一次测量估算；瘦体重不等于肌肉量。"} ?: "记录体重和体脂率后查看估算。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        } }
        item { Text("今日测量",style=MaterialTheme.typography.titleMedium) }
        if(today.isEmpty()) item { Text("今天还没有身体测量。",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        items(today,key={"today:${it.id}"}) { r -> Panel { RecordRow(r) {detail(r)} } }
        item { TextButton(onClick={history=!history}) {Text(if(history) "收起历史测量" else "查看历史测量 · ${measurements.size} 条")} }
        if(history) items(measurements,key={"history:${it.id}"}) { r -> RecordRow(r) {detail(r)} }
    }
}
@Composable internal fun OverviewValue(label:String,value:String) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        if(LocalDensity.current.fontScale>1.3f || maxWidth<280.dp) Column(verticalArrangement=Arrangement.spacedBy(4.dp)) {
            Text(label,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value,style=MaterialTheme.typography.bodyMedium)
        } else Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            Text(label,Modifier.weight(1f),style=MaterialTheme.typography.bodyMedium)
            Text(value,Modifier.weight(1f),style=MaterialTheme.typography.bodyMedium,textAlign=TextAlign.End)
        }
    }
}
