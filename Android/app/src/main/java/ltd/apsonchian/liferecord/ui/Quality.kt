@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import kotlinx.coroutines.delay

@Composable fun QualityReview(vm: AppViewModel, snapshot: Snapshot, dismiss: () -> Unit, detail: (Record) -> Unit, notify: (String) -> Unit) {
    val acknowledged by vm.acknowledgedQuality.collectAsState()
    var confirmed by rememberSaveable { mutableStateOf(false) }
    var confirming by remember { mutableStateOf<RecordQuality.Issue?>(null) }
    var at by remember { mutableDoubleStateOf(now()) }
    LaunchedEffect(Unit) { while(true) { delay(60_000); at = now() } }
    val issues = RecordQuality.issues(snapshot.records, at)
    val visible = issues.filter { (it.id in acknowledged) == confirmed }
    SubPage("记录质量检查", dismiss) {
        Text("检查全部真实记录：疑似重复餐食、营养数值、AI 信息不足、身体数值及短期跳变、训练时长和未来时间。提示是核对线索，不代表记录错误。", color = MaterialTheme.colorScheme.onSurfaceVariant)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            listOf(false to "待核对", true to "已确认").forEachIndexed { index, (value, title) ->
                SegmentedButton(selected = confirmed == value, onClick = { confirmed = value }, shape = SegmentedButtonDefaults.itemShape(index, 2)) { Text(title) }
            }
        }
        if(visible.isEmpty()) Empty(if(confirmed) "暂无已确认记录" else "暂无待核对记录", "检查不自动修改或删除数据，示例数据不参与检查。")
        visible.forEach { issue -> Panel {
            Text(issue.title, style = MaterialTheme.typography.titleMedium, color = if(confirmed) MaterialTheme.colorScheme.onSurfaceVariant else Carbs)
            Text("${issue.type.label} · ${issue.date.localText()}", style = MaterialTheme.typography.bodySmall)
            Text(issue.detail)
            issue.recordIDs.forEach { id -> snapshot.records.firstOrNull { it.id == id && it.type == issue.type }?.let { r -> RecordRow(r) { detail(r) } } }
            TextButton(onClick = { if(!confirmed) confirming = issue else runCatching { vm.confirmQuality(issue, false) }.onFailure { notify(it.message.orEmpty()) } }) { Text(if(confirmed) "重新核对" else "确认记录无误") }
        } }
        Text("“确认无误”仅隐藏当前版本的提示，保存在本机；记录被修改或同步更新后会重新检查。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    confirming?.let { issue -> GlassAlertDialog(onDismissRequest = { confirming = null }, title = { Text("确认记录无误？") }, text = { Text("只隐藏这条核对提示，原始记录保持不变。") },
        confirmButton = { TextButton(onClick = { runCatching { vm.confirmQuality(issue, true) }.onFailure { notify(it.message.orEmpty()) }; confirming = null }) { Text("确认无误") } },
        dismissButton = { TextButton(onClick = { confirming = null }) { Text("取消") } }) }
}
