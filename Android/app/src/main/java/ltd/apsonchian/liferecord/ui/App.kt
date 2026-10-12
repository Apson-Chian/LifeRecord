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
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalDensity
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
    var coachDraft by rememberSaveable { mutableStateOf("") }
    var mealHistory by remember { mutableStateOf<Boolean?>(null) }
    val pages = rememberSaveableStateHolder()
    val sourceLayer = rememberGraphicsLayer()
    val backdrop = remember(sourceLayer) { GlassBackdrop(sourceLayer) }
    val keyboardVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    val snack = remember { SnackbarHostState() }; val scope = rememberCoroutineScope()
    val notify: (String) -> Unit = { scope.launch { snack.showSnackbar(it) } }
    if(first) { Onboarding(vm); return@LifeTheme }
    BackHandler(enabled = tab != 0) { tab = 0 }
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Box(Modifier.fillMaxSize().glassSource(backdrop)) {
            AppBackground()
            Box(Modifier.fillMaxSize().statusBarsPadding()) {
                pages.SaveableStateProvider(tab) {
                    when(tab) {
                        0 -> Today(vm, snapshot, date, { dateText = it.toString() }, { detail = it }, { type -> editor = Record.create(type, date.epochAt()).apply {
                            if(type == RecordType.BODY) json.put("weight", snapshot.records.filter { it.type == RecordType.BODY }.maxByOrNull { it.date }?.json?.optDouble("weight") ?: snapshot.profile.optDouble("baselineWeight"))
                            if(type == RecordType.WORKOUT) { json.put("date", minOf(this.date, now())); json.put("endDate", minOf(this.date + 3600, now())) }
                        } }, notify, { editor = it.copy() },
                            { draft -> coachDraft = draft; tab = 2 }, { photos -> mealHistory = photos })
                        1 -> Trends(vm, snapshot, { detail = it }, { tab = 2; coachDraft = "请结合最近七天的饮食、身体测量和训练，生成周报，说明记录覆盖与下周行动，不修改记录。" })
                        2 -> Box(Modifier.fillMaxSize().padding(bottom = if(keyboardVisible) 0.dp else glassPageBottomPadding() - 16.dp)) {
                            Coach(vm, notify, coachDraft) { coachDraft = "" }
                        }
                        3 -> Settings(vm, snapshot, notify)
                    }
                }
            }
        }
        if(!keyboardVisible) GlassNavigationBar(backdrop, tab, { tab = it }, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 20.dp, vertical = 10.dp))
        SnackbarHost(snack, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().imePadding().padding(bottom = if(keyboardVisible) 8.dp else glassBarHeight() + 24.dp))
    }
    mealHistory?.let { photos -> MealHistory(vm, snapshot, photos, { mealHistory = null }, { detail = it }) }
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
    val color = MaterialTheme.colorScheme.primary
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(26.dp), color = MaterialTheme.colorScheme.surface, border = BorderStroke(1.dp, color.copy(alpha = .13f))) {
        Column(Modifier.background(Brush.linearGradient(listOf(color.copy(alpha = .055f), Color.Transparent))).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}
@Composable fun Empty(title: String, text: String) { Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) { Text(title, style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(8.dp)); Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
@Composable fun Today(vm: AppViewModel, s: Snapshot, date: LocalDate, select: (LocalDate) -> Unit, detail: (Record) -> Unit, add: (RecordType) -> Unit, notify: (String) -> Unit, edit: (Record) -> Unit, coach: (String) -> Unit, history: (Boolean) -> Unit) {
    var datePicker by remember { mutableStateOf(false) }
    var addMenu by remember { mutableStateOf(false) }
    val meals = Insights.daily(s.records, date)
    val body = s.records.filter { it.type == RecordType.BODY }.maxByOrNull { it.date }
    val workouts = s.records.filter { it.type == RecordType.WORKOUT && it.date.day() == date }.sortedByDescending { it.date }
    val status by vm.status.collectAsState()
    val activeWorkout = s.records.firstOrNull { it.type == RecordType.WORKOUT && it.json.isNull("endDate") }
    var liveNow by remember { mutableDoubleStateOf(now()) }
    LaunchedEffect(activeWorkout?.id) { if(activeWorkout != null) while(true) { liveNow = now(); delay(1000) } }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 20.dp, 16.dp, glassPageBottomPadding()), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        item {
            val greeting = when { LocalTime.now().hour < 11 -> "早上好"; LocalTime.now().hour < 18 -> "今天状态如何"; else -> "晚上好" }
            val name = s.profile.optString("displayName")
            PageTitle(greeting + if(name.isBlank()) "" else "，$name", "生活记录") {
                Box {
                    OutlinedIconButton(onClick = { addMenu = true }, border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = .24f))) { Icon(Icons.Default.Add, "添加记录", tint = MaterialTheme.colorScheme.primary) }
                    DropdownMenu(expanded = addMenu, onDismissRequest = { addMenu = false }) {
                        DropdownMenuItem(text = { Text("记一餐") }, onClick = { addMenu = false; add(RecordType.MEAL) })
                        DropdownMenuItem(text = { Text("记体重") }, onClick = { addMenu = false; add(RecordType.BODY) })
                    }
                }
            }
        }
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
        if(meals.any { it.demo } || s.records.any { it.demo && it.type == RecordType.BODY }) item { Panel { Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { Text("完整示例数据已写入", style = MaterialTheme.typography.titleMedium); Text("首页、趋势、教练都会展示对应效果", style = MaterialTheme.typography.bodySmall) }
            TextButton(onClick = vm::clearDemo) { Text("清除") }
        } } }
        item { Panel {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(s.profile.optString("fitnessGoal"), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.titleMedium); Text("每日目标", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary) }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Ring(Modifier.size(116.dp), listOf((Insights.total(meals,"protein") / s.profile.optDouble("proteinGoal")).toFloat(), (Insights.total(meals,"carbs") / s.profile.optDouble("carbsGoal")).toFloat(), meals.size/4f), 11f)
                Spacer(Modifier.width(20.dp)); Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Metric("蛋白质", "${format(Insights.total(meals,"protein"))} / ${format(s.profile.optDouble("proteinGoal"))} g", Protein)
                    Metric("碳水", "${format(Insights.total(meals,"carbs"))} / ${format(s.profile.optDouble("carbsGoal"))} g", Carbs)
                    Metric("体重", body?.title ?: "暂无记录", MaterialTheme.colorScheme.primary)
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("${format(Insights.total(meals,"calories"))} 千卡", style = MaterialTheme.typography.headlineMedium)
                val remaining = s.profile.optDouble("calorieGoal") - Insights.total(meals,"calories")
                Text(if(remaining >= 0) "还差 ${format(remaining)} 千卡" else "超出 ${format(-remaining)} 千卡", style = MaterialTheme.typography.bodyMedium)
            }
        } }
        item { Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ActionTile("记一餐", "拍照识别 · 手动记录", MaterialTheme.colorScheme.primary, Modifier.weight(1f)) { add(RecordType.MEAL) }
            ActionTile("记体重", "追踪趋势", Protein, Modifier.weight(1f)) { add(RecordType.BODY) }
        } }
        item { Panel {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text("健身记录", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f)); TextButton(onClick = { add(RecordType.WORKOUT) }) { Text("补记") } }
            if(date == LocalDate.now()) {
                val active = activeWorkout
                Button(onClick = { runCatching {
                    if(active == null) vm.startWorkout() else {
                        vm.endWorkout(active)
                        vm.snapshot.value.records.firstOrNull { it.id == active.id }?.let(edit)
                    }
                }.onFailure { notify(it.message ?: "保存失败") } }, Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF0D6E6E), contentColor = Color.White)) { Text(if(active == null) "开始训练" else "结束训练 · ${format((liveNow - active.date)/60)} 分钟") }
            } else if(workouts.isEmpty()) Text("这一天还没有训练记录", color = MaterialTheme.colorScheme.onSurfaceVariant)
            workouts.forEach { r -> RecordRow(r, { detail(r) }) }
        } }
        item { Panel {
            Text("营养目标", style = MaterialTheme.typography.titleLarge)
            listOf(Triple("蛋白质", "protein", Protein), Triple("碳水", "carbs", Carbs), Triple("脂肪", "fat", Fat)).forEach { (label, key, color) ->
                val value = Insights.total(meals, key); val goal = s.profile.optDouble("${key}Goal")
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(label, style = MaterialTheme.typography.bodyMedium); Text("${format(value)} / ${format(goal)} g", style = MaterialTheme.typography.bodyMedium) }
                LinearProgressIndicator(progress = { (value / goal).toFloat().coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().height(7.dp).clip(RoundedCornerShape(4.dp)), color = color, trackColor = color.copy(alpha = .12f))
            }
        } }
        item { Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text("饮食记录", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f)); TextButton(onClick = { history(true) }) { Text("照片") }; TextButton(onClick = { history(false) }) { Text("查看全部") } } }
        if(meals.isEmpty()) item { Panel { Empty("第一餐，从这里开始", "手动记录，或让 AI 帮你分析照片") } }
        listOf("早餐", "午餐", "晚餐", "加餐").forEach { kind ->
            val group = meals.filter { it.json.optString("kind") == kind }
            if(group.isNotEmpty()) item { Panel { Text(kind, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary); group.sortedByDescending { it.date }.forEach { r -> RecordRow(r, { detail(r) }) } } }
        }
        val measurements = s.records.filter { it.type == RecordType.BODY && it.date.day() == date }
        if(measurements.isNotEmpty()) item { Panel { Text("身体测量", style = MaterialTheme.typography.titleLarge); measurements.forEach { RecordRow(it, { detail(it) }) } } }
        item { Panel(Modifier.clickable { coach("请根据我在 $date 的饮食和训练，给出可执行的下一步建议，不修改记录。") }) { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text("今日提示", style = MaterialTheme.typography.titleMedium); Text("问 AI", color = MaterialTheme.colorScheme.primary) }; Text(if(meals.isEmpty()) "先记下第一餐，让今天的进步有迹可循。" else "已记录 ${meals.size} 餐，蛋白质 ${format(Insights.total(meals,"protein"))} g。结合训练安排下一餐。", style = MaterialTheme.typography.bodyMedium) } }
        item { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(status, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant); TextButton(onClick = vm::sync) { Text("同步") } } }
    }
    if(datePicker) RecordCalendar(date, s.records, { datePicker = false }, select)
}
@Composable fun Metric(label: String, value: String, color: Color) { Row(verticalAlignment = Alignment.CenterVertically) { Box(Modifier.size(7.dp).background(color, RoundedCornerShape(4.dp))); Spacer(Modifier.width(8.dp)); Column { Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant); Text(value, style = MaterialTheme.typography.labelLarge) } } }
@Composable fun Ring(modifier: Modifier, values: List<Float>, thickness: Float) {
    val track = MaterialTheme.colorScheme.surfaceVariant
    Canvas(modifier) {
        val stroke = thickness.dp.toPx(); val gap = 0f
        values.forEachIndexed { i, value -> val inset = stroke/2+i*(stroke+gap); val diameter = size.minDimension-2*inset
            if(diameter > 0) { drawArc(track, -90f, 360f, false, androidx.compose.ui.geometry.Offset(inset,inset), androidx.compose.ui.geometry.Size(diameter,diameter), style = Stroke(stroke)); drawArc(listOf(Protein,Carbs,Meals)[i], -90f, value.coerceIn(0f,1f)*360, false, androidx.compose.ui.geometry.Offset(inset,inset), androidx.compose.ui.geometry.Size(diameter,diameter), style = Stroke(stroke, cap = StrokeCap.Round)) }
        }
    }
}
@Composable fun ActionTile(title: String, subtitle: String, tint: Color, modifier: Modifier, action: () -> Unit) {
    Panel(modifier.clickable(onClick = action)) {
        ActionGlyph(title == "记一餐", tint)
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable private fun ActionGlyph(meal: Boolean, tint: Color) {
    Canvas(Modifier.size(26.dp)) {
        val scale = size.width / 24f
        fun point(x: Float, y: Float) = androidx.compose.ui.geometry.Offset(x * scale, y * scale)
        val stroke = Stroke(1.8f * scale, cap = StrokeCap.Round, join = StrokeJoin.Round)
        if(meal) {
            val path = Path().apply {
                moveTo(4*scale, 2*scale); lineTo(4*scale, 7*scale); quadraticTo(4*scale, 10*scale, 8*scale, 10*scale)
                quadraticTo(12*scale, 10*scale, 12*scale, 7*scale); lineTo(12*scale, 2*scale)
                moveTo(8*scale, 2*scale); lineTo(8*scale, 22*scale)
                moveTo(20*scale, 2*scale); quadraticTo(15*scale, 6*scale, 16*scale, 12*scale); lineTo(20*scale, 12*scale); lineTo(20*scale, 22*scale); lineTo(20*scale, 2*scale)
            }
            drawPath(path, tint, style = stroke)
        } else {
            drawRoundRect(tint, point(3f, 3f), androidx.compose.ui.geometry.Size(18*scale, 18*scale), androidx.compose.ui.geometry.CornerRadius(4*scale), style = stroke)
            drawArc(tint, 180f, 180f, false, point(7f, 6f), androidx.compose.ui.geometry.Size(10*scale, 10*scale), style = stroke)
            drawLine(tint, point(12f, 11f), point(15f, 8f), 1.8f*scale, StrokeCap.Round)
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
