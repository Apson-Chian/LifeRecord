package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.data.*

@Composable fun BodyOverviewPage(records:List<Record>,dismiss:()->Unit,detail:(Record)->Unit) {
    val preview=records.any {it.demo} && records.none {!it.demo && it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT)}
    val summary=BodyOverview.summarize(records,includeDemo=preview)
    SubPage("身体总览",dismiss) {
        if(preview) Text("示例预览 · 合成身体测量",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.primary)
        Panel {
            Text("趋势体重",style=MaterialTheme.typography.titleMedium)
            Text(summary.points.lastOrNull()?.trend?.let {"${format(it)} kg"} ?: "—",style=MaterialTheme.typography.headlineLarge)
            OverviewValue("今日中位数",summary.today?.value?.let {"${format(it)} kg"} ?: "—")
            OverviewValue("今日测量",summary.today?.count?.let {"$it 次"} ?: "—")
            OverviewValue("近 7 天变化",summary.change7?.let {"${signed(it)} kg"} ?: "记录不足")
            OverviewValue("近 30 天变化",summary.change30?.let {"${signed(it)} kg"} ?: "记录不足")
            OverviewValue("趋势变化速度",summary.weeklyRate?.let {"${signed(it)} kg/周"} ?: "记录不足")
        }
        Panel {
            Text("每日中位数与趋势",style=MaterialTheme.typography.titleMedium)
            if(summary.points.isEmpty()) Empty("暂无测量","记录体重后查看变化") else TrendChart(summary.points,"kg",MaterialTheme.colorScheme.primary,true)
        }
        Panel(tint=Fat) {
            Text("身体组成",style=MaterialTheme.typography.titleMedium)
            OverviewValue("体脂率",summary.composition?.json?.getDouble("bodyFat")?.let {"${format(it)}%"} ?: "—")
            OverviewValue("脂肪量",summary.fatMass?.let {"${format(it)} kg"} ?: "—")
            OverviewValue("瘦体重",summary.leanMass?.let {"${format(it)} kg"} ?: "—")
            Text(summary.composition?.let {"依据 ${it.date.localText()} 同一次测量估算；瘦体重不等于肌肉量。"} ?: "记录体重和体脂率后查看估算。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text("原始测量",style=MaterialTheme.typography.titleMedium)
        records.filter {it.type==RecordType.BODY && (preview || !it.demo) && it.date<=now()}.sortedByDescending {it.date}.forEach { r -> RecordRow(r) {detail(r)} }
    }
}
@Composable internal fun OverviewValue(label:String,value:String) {
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {Text(label,style=MaterialTheme.typography.bodyMedium);Text(value,style=MaterialTheme.typography.bodyMedium)}
}
