@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package ltd.apsonchian.liferecord.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import java.time.*
import java.time.format.DateTimeFormatter

@Composable fun LifeRecordApp(vm: AppViewModel) = LifeTheme {
    val snapshot by vm.snapshot.collectAsState()
    val first by vm.onboarding.collectAsState()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var dateText by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    val date = LocalDate.parse(dateText)
    val todayRequest by vm.todayRequest.collectAsState()
    LaunchedEffect(todayRequest) { if(todayRequest > 0) { tab = 0; dateText = LocalDate.now().toString() } }
    var editor by remember { mutableStateOf<Record?>(null) }
    var detail by remember { mutableStateOf<Record?>(null) }
    var chooseType by remember { mutableStateOf(false) }
    val snack = remember { SnackbarHostState() }; val scope = rememberCoroutineScope()
    val notify: (String) -> Unit = { scope.launch { snack.showSnackbar(it) } }
    if(first) { Onboarding(vm); return@LifeTheme }
    BackHandler(enabled = tab != 0) { tab = 0 }
    Scaffold(snackbarHost = { SnackbarHost(snack) }, bottomBar = {
        NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
            val labels = listOf("今日", "趋势", "教练", "设置")
            val icons = listOf(Icons.Default.Home, Icons.Default.DateRange, Icons.Default.Person, Icons.Default.Settings)
            labels.forEachIndexed { i, title -> NavigationBarItem(selected = tab == i, onClick = { tab = i }, icon = { Icon(icons[i], title) }, label = { Text(title) }) }
        }
    }) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when(tab) {
                0 -> Today(vm, snapshot, date, { dateText = it.toString() }, { detail = it }, { editor = Record.create(it, date.epochAt()) }, notify, { chooseType = true })
                1 -> Trends(vm, snapshot, { detail = it }, { tab = 2; vm.send("请结合最近七天的饮食、身体测量和训练，生成周报，说明记录覆盖与下周行动，不修改记录。") })
                2 -> Coach(vm, notify)
                3 -> Settings(vm, snapshot, notify)
            }
        }
    }
    if(chooseType) ModalBottomSheet(onDismissRequest = { chooseType = false }) {
        Column(Modifier.fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("记录生活的一小步", style = MaterialTheme.typography.titleLarge)
            listOf(RecordType.MEAL, RecordType.BODY, RecordType.WORKOUT).forEach { type -> OutlinedButton(onClick = { chooseType = false; editor = Record.create(type, date.epochAt()).apply { if(type == RecordType.WORKOUT) json.put("endDate", date.epochAt()) } }, Modifier.fillMaxWidth()) { Text("记录${type.label}") } }
            Spacer(Modifier.height(16.dp))
        }
    }
    detail?.let { selected ->
        val current = snapshot.records.find { it.id == selected.id && it.type == selected.type }
        if(current == null) { detail = null } else RecordDetail(vm, current, { detail = null }, { detail = null; editor = current.copy() }, notify)
    }
    editor?.let { RecordEditor(vm, it, { editor = null }, notify) }
}
@Composable fun PageTitle(title: String, subtitle: String, trailing: @Composable (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.height(4.dp)); Text(title, style = MaterialTheme.typography.headlineLarge) }
        trailing?.invoke()
    }
}
@Composable fun Panel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content) }
}
@Composable fun Empty(title: String, text: String) { Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) { Text(title, style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(8.dp)); Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
@Composable fun Today(vm: AppViewModel, s: Snapshot, date: LocalDate, select: (LocalDate) -> Unit, detail: (Record) -> Unit, add: (RecordType) -> Unit, notify: (String) -> Unit, onAdd: () -> Unit) {
    var datePicker by remember { mutableStateOf(false) }
    val meals = Insights.daily(s.records, date)
    val body = s.records.filter { it.type == RecordType.BODY && it.date.day() <= date }.maxByOrNull { it.date }
    val workouts = s.records.filter { it.type == RecordType.WORKOUT && it.date.day() == date }.sortedByDescending { it.date }
    val status by vm.status.collectAsState()
    val activeWorkout = s.records.firstOrNull { it.type == RecordType.WORKOUT && it.json.isNull("endDate") }
    var liveNow by remember { mutableDoubleStateOf(now()) }
    LaunchedEffect(activeWorkout?.id) { if(activeWorkout != null) while(true) { liveNow = now(); delay(1000) } }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(20.dp, 20.dp, 20.dp, 100.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        item { PageTitle(if(date == LocalDate.now()) "今天，也在进步" else "每天，都有记录", s.profile.optString("displayName").ifBlank { "生活记录" }) { FilledIconButton(onClick = onAdd) { Icon(Icons.Default.Add, "添加记录") } } }
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { select(date.minusDays(1)) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "前一天") }
                TextButton(onClick = { datePicker = true }, Modifier.weight(1f)) { Text(date.format(DateTimeFormatter.ofPattern("M 月 d 日 · E", java.util.Locale.CHINA))) }
                IconButton(onClick = { select(date.plusDays(1)) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "后一天") }
                if(date != LocalDate.now()) TextButton(onClick = { select(LocalDate.now()) }) { Text("今天") }
            }
            val monday = date.minusDays((date.dayOfWeek.value - 1).toLong())
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                (0L..6L).forEach { i -> val d = monday.plusDays(i); val entries = Insights.daily(s.records, d)
                    Column(Modifier.widthIn(min = 38.dp).clip(RoundedCornerShape(16.dp)).background(if(d == date) MaterialTheme.colorScheme.surfaceVariant else Color.Transparent).clickable { select(d) }.padding(vertical = 9.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(listOf("一","二","三","四","五","六","日")[i.toInt()], style = MaterialTheme.typography.labelSmall)
                        Spacer(Modifier.height(6.dp)); Ring(Modifier.size(28.dp), listOf((Insights.total(entries,"protein") / s.profile.optDouble("proteinGoal")).toFloat(), (Insights.total(entries,"carbs") / s.profile.optDouble("carbsGoal")).toFloat(), entries.size/4f), 2f)
                        Spacer(Modifier.height(5.dp)); Text(d.dayOfMonth.toString(), style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
        item { Panel {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(150.dp), contentAlignment = Alignment.Center) {
                    Ring(Modifier.fillMaxSize(), listOf((Insights.total(meals,"protein") / s.profile.optDouble("proteinGoal")).toFloat(), (Insights.total(meals,"carbs") / s.profile.optDouble("carbsGoal")).toFloat(), meals.size/4f), 12f)
                    Column(horizontalAlignment = Alignment.CenterHorizontally) { Text(format(Insights.total(meals,"calories")), style = MaterialTheme.typography.headlineMedium); Text("kcal 已摄入", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                Spacer(Modifier.width(20.dp)); Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Metric("蛋白质", "${format(Insights.total(meals,"protein"))} / ${format(s.profile.optDouble("proteinGoal"))} g", Protein)
                    Metric("碳水", "${format(Insights.total(meals,"carbs"))} / ${format(s.profile.optDouble("carbsGoal"))} g", Carbs)
                    Metric("用餐", "${meals.size} / 4 次", Meals)
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("目标 ${format(s.profile.optDouble("calorieGoal"))} kcal", style = MaterialTheme.typography.bodyMedium)
                Text("脂肪 ${format(Insights.total(meals,"fat"))} g", style = MaterialTheme.typography.bodyMedium)
            }
        } }
        item { Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Panel(Modifier.weight(1f).clickable { add(RecordType.BODY) }) { Text("最近体重", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant); Text(body?.title ?: "尚未测量", style = MaterialTheme.typography.titleLarge); Text(body?.date?.day()?.toString() ?: "点此记录身体数据", style = MaterialTheme.typography.labelSmall) }
            Panel(Modifier.weight(1f)) { Text("记录连续性", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant); Text("${Insights.streak(s.records)} 天", style = MaterialTheme.typography.titleLarge); Text("每一次记录都算数", style = MaterialTheme.typography.labelSmall) }
        } }
        item { Panel {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text("健身记录", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f)); TextButton(onClick = { add(RecordType.WORKOUT) }) { Text("补记") } }
            if(date == LocalDate.now()) {
                val active = activeWorkout
                Button(onClick = { runCatching { if(active == null) vm.startWorkout() else vm.endWorkout(active) }.onFailure { notify(it.message ?: "保存失败") } }, Modifier.fillMaxWidth()) { Text(if(active == null) "开始训练" else "结束训练 · ${format((liveNow - active.date)/60)} 分钟") }
            } else if(workouts.isEmpty()) Text("这一天还没有训练记录", color = MaterialTheme.colorScheme.onSurfaceVariant)
            workouts.forEach { r -> RecordRow(r, { detail(r) }) }
        } }
        item { Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text("今天吃了什么", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f)); TextButton(onClick = { add(RecordType.MEAL) }) { Text("记一餐") } } }
        if(meals.isEmpty()) item { Panel { Empty("第一餐，从这里开始", "手动记录，或让 AI 帮你分析照片") } }
        items(meals.sortedByDescending { it.date }, key = { it.id }) { r -> Panel { RecordRow(r, { detail(r) }) } }
        val measurements = s.records.filter { it.type == RecordType.BODY && it.date.day() == date }
        if(measurements.isNotEmpty()) item { Panel { Text("身体测量", style = MaterialTheme.typography.titleLarge); measurements.forEach { RecordRow(it, { detail(it) }) } } }
        item { Text(status, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    if(datePicker) {
        val state = rememberDatePickerState(initialSelectedDateMillis = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(onDismissRequest = { datePicker = false }, confirmButton = { TextButton(onClick = { state.selectedDateMillis?.let { select(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }; datePicker = false }) { Text("选择") } }, dismissButton = { TextButton(onClick = { datePicker = false }) { Text("取消") } }) { DatePicker(state, title = { Text("选择记录日期", Modifier.padding(24.dp)) }) }
    }
}
@Composable fun Metric(label: String, value: String, color: Color) { Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(7.dp).background(color, RoundedCornerShape(4.dp))); Spacer(Modifier.width(8.dp)); Column { Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant); Text(value, style = MaterialTheme.typography.labelLarge) } } }
@Composable fun Ring(modifier: Modifier, values: List<Float>, thickness: Float) {
    val track = MaterialTheme.colorScheme.surfaceVariant
    Canvas(modifier) {
        val stroke = thickness.dp.toPx(); val gap = stroke*0.35f
        values.forEachIndexed { i, value -> val inset = stroke/2+i*(stroke+gap); val diameter = size.minDimension-2*inset
            if(diameter > 0) { drawArc(track, -90f, 360f, false, androidx.compose.ui.geometry.Offset(inset,inset), androidx.compose.ui.geometry.Size(diameter,diameter), style = Stroke(stroke)); drawArc(listOf(Protein,Carbs,Meals)[i], -90f, value.coerceIn(0f,1f)*360, false, androidx.compose.ui.geometry.Offset(inset,inset), androidx.compose.ui.geometry.Size(diameter,diameter), style = Stroke(stroke, cap = StrokeCap.Round)) }
        }
    }
}
@Composable fun RecordRow(r: Record, onClick: () -> Unit) { Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
    Column(Modifier.weight(1f)) { Text(r.title, style = MaterialTheme.typography.titleMedium); Text(when(r.type) {
        RecordType.MEAL -> "${r.json.optString("kind")} · ${format(r.json.optDouble("calories"))} kcal · ${r.json.optString("source")}" + if(r.demo) " · 示例" else ""
        RecordType.BODY -> r.date.day().toString() + if(r.demo) " · 示例" else ""
        RecordType.WORKOUT -> if(r.json.isNull("endDate")) "正在训练" else "${format((r.json.optDouble("endDate") - r.date)/60)} 分钟 · ${r.date.day()}"
        RecordType.FAVORITE -> "${r.json.optString("portion", "1 份")} · ${format(r.json.optDouble("calories"))} kcal"
        RecordType.EXERCISE -> r.json.optString("bodyPart", "未分类")
    }, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "查看详情", tint = MaterialTheme.colorScheme.onSurfaceVariant)
} }
@Composable fun Onboarding(vm: AppViewModel) {
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).systemBarsPadding().padding(28.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Spacer(Modifier.height(36.dp)); Ring(Modifier.size(140.dp), listOf(0.82f,0.64f,0.72f), 12f)
        Text("把进步，\n记在每一天", style = MaterialTheme.typography.headlineLarge)
        Text("饮食、训练和身体变化，在一个地方看见。", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Panel { Text("一处记录，随时回顾", style = MaterialTheme.typography.titleMedium); Text("离线记录随时可用；配置私有同步密钥后，可与 iOS 和网页共享数据。AI 接口由你选择。") }
        Text("记录保存在本机。仅在你启用同步或使用 AI 时，相关数据会发送至配置的服务。", style = MaterialTheme.typography.bodyMedium)
        Button(onClick = { vm.completeOnboarding() }, Modifier.fillMaxWidth().height(54.dp)) { Text("开始我的记录") }
        OutlinedButton(onClick = { vm.seedDemo(); vm.completeOnboarding() }, Modifier.fillMaxWidth()) { Text("先看看示例数据") }
    }
}
