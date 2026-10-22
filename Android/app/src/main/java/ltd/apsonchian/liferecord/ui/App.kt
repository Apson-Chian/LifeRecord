@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package ltd.apsonchian.liferecord.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight

import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.semantics.*
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import java.time.*
import java.time.format.DateTimeFormatter

@Composable fun LifeRecordApp(vm: AppViewModel) {
    val mode by vm.appearance.collectAsState(); val color by vm.accent.collectAsState()
    LifeTheme(mode,color) {
    val generation by vm.dataGeneration.collectAsState()
    val snapshot by vm.snapshot.collectAsState()
    val first by vm.onboarding.collectAsState()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var dateText by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    val date = LocalDate.parse(dateText)
    val preview = DemoData.isPreview(snapshot.records)
    val displaySnapshot = if (preview) snapshot.copy(profile = DemoData.profile()) else snapshot
    val latestExample = snapshot.records.filter { it.demo && it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) }.maxByOrNull { it.date }
    LaunchedEffect(preview, latestExample?.id) {
        if (preview && date == LocalDate.now() && snapshot.records.none { it.demo && it.date.day() == date && it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) }) {
            latestExample?.let { dateText = it.date.day().toString() }
        }
    }
    val todayRequest by vm.todayRequest.collectAsState()
    LaunchedEffect(todayRequest) { if(todayRequest > 0) { tab = 0; dateText = LocalDate.now().toString() } }
    var editor by rememberSaveable(stateSaver = OptionalRecordSaver) { mutableStateOf<Record?>(null) }
    var detail by rememberSaveable(stateSaver = OptionalRecordSaver) { mutableStateOf<Record?>(null) }
    var coachDraft by rememberSaveable { mutableStateOf("") }
    var mealHistory by rememberSaveable { mutableStateOf<Boolean?>(null) }
    var restoredGeneration by remember { mutableIntStateOf(generation) }
    LaunchedEffect(generation) { if (restoredGeneration != generation) { editor=null;detail=null;coachDraft="";mealHistory=null;restoredGeneration=generation } }
    val pages = key(generation) { rememberSaveableStateHolder() }
    val sourceLayer = rememberGraphicsLayer()
    val backdrop = remember(sourceLayer) { GlassBackdrop(sourceLayer) }
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val keyboardVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    val snack = remember { SnackbarHostState() }; val scope = rememberCoroutineScope()
    val notify: (String) -> Unit = { scope.launch { snack.showSnackbar(it) } }
    if(first) { Onboarding(vm); return@LifeTheme }
    BackHandler(enabled = tab != 0) { tab = 0 }
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).dismissKeyboardOnBackgroundTap()) {
        Box(Modifier.fillMaxSize().glassSource(backdrop)) {
            AppBackground()
            Box(Modifier.fillMaxSize().statusBarsPadding()) {
                pages.SaveableStateProvider(tab) {
                    when(tab) {
                        0 -> Today(vm, displaySnapshot, date, { dateText = it.toString() }, { detail = it }, { type -> editor = Record.create(type, date.epochAt()).apply {
                            if(type == RecordType.BODY) json.put("weight", snapshot.records.filter { it.type == RecordType.BODY }.maxByOrNull { it.date }?.json?.optDouble("weight") ?: snapshot.profile.optDouble("baselineWeight"))
                            if(type == RecordType.WORKOUT) { json.put("date", minOf(this.date, now())); json.put("endDate", minOf(this.date + 3600, now())) }
                        } }, notify, { editor = it.copy() },
                            { draft -> coachDraft = draft; tab = 2 }, { photos -> mealHistory = photos })
                        1 -> Trends(vm, displaySnapshot, { detail = it }, { draft -> tab = 2; coachDraft = draft }, notify, {editor=it.copy()})
                        2 -> Box(Modifier.fillMaxSize().padding(bottom = if(keyboardVisible) 0.dp else glassPageBottomPadding() - 16.dp)) {
                            Coach(vm, notify, coachDraft) { coachDraft = "" }
                        }
                        3 -> Settings(vm, snapshot, notify)
                    }
                }
            }
        }
        if (!keyboardVisible) {
            val navigationInset = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }
            ProgressiveBackdrop(backdrop, Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                .height(glassBarHeight() + 64.dp + navigationInset).testTag("navigation-progressive-blur"))
            GlassNavigationBar(backdrop, tab, { focus.clearFocus(force=true);keyboard?.hide();tab = it }, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp))
        }
        SnackbarHost(snack, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().imePadding().padding(bottom = if(keyboardVisible) 8.dp else glassBarHeight() + 24.dp)) { data ->
            Surface(Modifier.padding(horizontal=24.dp).testTag("status-message"),shape=RoundedCornerShape(50),color=MaterialTheme.colorScheme.surface.copy(alpha=.97f),shadowElevation=8.dp,border=BorderStroke(.7.dp,MaterialTheme.colorScheme.primary.copy(alpha=.12f))) {
                Text(data.visuals.message,Modifier.padding(horizontal=18.dp,vertical=12.dp),style=MaterialTheme.typography.bodyMedium)
            }
        }
    }
    mealHistory?.let { photos -> MealHistory(vm, snapshot, photos, { mealHistory = null }, { detail = it }) }
    detail?.let { selected ->
        val current = snapshot.records.find { it.id == selected.id && it.type == selected.type }
        if(current == null) { detail = null } else RecordDetail(vm, current, { detail = null }, { detail = null; editor = current.copy() }, notify)
    }
    editor?.let { RecordEditor(vm, it, { editor = null }, notify) }
}
}

@Composable fun PageTitle(title: String, subtitle: String, trailing: @Composable (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().heightIn(min=72.dp).semantics {contentDescription=subtitle},
        verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        Text(title,Modifier.weight(1f).testTag("page-title").semantics {heading()},style=MaterialTheme.typography.headlineLarge)
        trailing?.invoke()
    }
}
@Composable fun Panel(modifier: Modifier = Modifier, tint:Color=MaterialTheme.colorScheme.primary, radius:androidx.compose.ui.unit.Dp=26.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().cardMaterial(tint, radius).padding(20.dp),
        verticalArrangement=Arrangement.spacedBy(16.dp),content=content)
}
@Composable fun Empty(title: String, text: String) { Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) { Text(title, style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(8.dp)); Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
@Composable fun Today(vm: AppViewModel, s: Snapshot, date: LocalDate, select: (LocalDate) -> Unit, detail: (Record) -> Unit, add: (RecordType) -> Unit, notify: (String) -> Unit, edit: (Record) -> Unit, coach: (String) -> Unit, history: (Boolean) -> Unit) {
    var datePicker by remember { mutableStateOf(false) }
    var addMenu by remember { mutableStateOf(false) }
    val preview = s.records.none { !it.demo && it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) }
    val visible = s.records.filter { !it.demo || preview }
    val meals = Insights.daily(visible, date)
    val dayGoals = GoalHistory.at(s.profile,date)
    val body = visible.filter { it.type == RecordType.BODY }.maxByOrNull { it.date }
    val workouts = visible.filter { it.type == RecordType.WORKOUT && it.date.day() == date }.sortedByDescending { it.date }
    val status by vm.status.collectAsState()
    val syncing by vm.syncing.collectAsState()
    var refreshRequested by remember { mutableStateOf(false) }
    var pendingDelete by rememberSaveable(stateSaver = OptionalRecordSaver) { mutableStateOf<Record?>(null) }
    val feedback = rememberActionFeedback()
    LaunchedEffect(syncing, refreshRequested) {
        if (refreshRequested && !syncing) { notify(if (vm.app.secrets.get("sync").isBlank()) "请先在设置中登录账号或连接同步" else vm.status.value); refreshRequested = false }
    }
    val activeWorkout = s.records.firstOrNull { it.type == RecordType.WORKOUT && it.json.isNull("endDate") }
    var liveNow by remember { mutableDoubleStateOf(now()) }
    LaunchedEffect(activeWorkout?.id) { if(activeWorkout != null) while(true) { liveNow = now(); delay(1000) } }
    PullToRefreshBox(isRefreshing = syncing && refreshRequested, onRefresh = { refreshRequested = true; vm.sync() }, modifier = Modifier.fillMaxSize().testTag("today-pull-to-refresh")) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 20.dp, 16.dp, glassPageBottomPadding()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            val greeting = when { LocalTime.now().hour < 11 -> "早上好"; LocalTime.now().hour < 18 -> "今天状态如何"; else -> "晚上好" }
            val name = s.profile.optString("displayName")
            PageTitle(greeting + if(name.isBlank()) "" else "，$name", "${if(date==LocalDate.now()) "今日" else "回顾"} · ${date.format(DateTimeFormatter.ofPattern("M月d日 E",java.util.Locale.CHINA))}") {
                Box {
                    SymbolButton(Glyph.Plus,"添加记录",{addMenu=true})
                    DropdownMenu(expanded = addMenu, onDismissRequest = { addMenu = false }) {
                        DropdownMenuItem(text = { Text("记一餐") }, onClick = { addMenu = false; add(RecordType.MEAL) })
                        DropdownMenuItem(text = { Text("记体重") }, onClick = { addMenu = false; add(RecordType.BODY) })
                    }
                }
            }
        }
        item {
            Column(Modifier.fillMaxWidth().cardMaterial(radius=22.dp).padding(12.dp),verticalArrangement=Arrangement.spacedBy(11.dp)) {
                Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.primary.copy(alpha=.08f)).clickable {select(date.minusDays(1))},contentAlignment=Alignment.Center) { AppIcon(Glyph.Chevron,MaterialTheme.colorScheme.onSurface,Modifier.size(18.dp).graphicsLayer {rotationZ=180f},"前一天") }
                    Row(Modifier.weight(1f).heightIn(min=44.dp).clickable {datePicker=true},horizontalArrangement=Arrangement.Center,verticalAlignment=Alignment.CenterVertically) {
                        AppIcon(Glyph.Calendar,MaterialTheme.colorScheme.onSurface,Modifier.size(17.dp));Spacer(Modifier.width(6.dp))
                        Text(date.format(DateTimeFormatter.ofPattern("yyyy年M月d日 E",java.util.Locale.CHINA)),style=MaterialTheme.typography.bodyMedium.copy(fontWeight=FontWeight.SemiBold))
                    }
                    if(date!=LocalDate.now()) TextButton(onClick={select(LocalDate.now())}) {Text("今天",style=MaterialTheme.typography.labelMedium)}
                    Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.primary.copy(alpha=.08f)).clickable {select(date.plusDays(1))},contentAlignment=Alignment.Center) { AppIcon(Glyph.Chevron,MaterialTheme.colorScheme.onSurface,Modifier.size(18.dp),"后一天") }
                }
                val monday=date.minusDays((date.dayOfWeek.value-1).toLong())
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(2.dp)) {
                    (0L..6L).forEach { i -> val d=monday.plusDays(i);val entries=Insights.daily(visible,d);val selected=d==date
                        val dayMeals = entries.filter { it.type == RecordType.MEAL }
                        val ringGoals = GoalHistory.at(s.profile,d)
                        val protein = Insights.total(dayMeals, "protein") / ringGoals.optDouble("proteinGoal").coerceAtLeast(1.0)
                        val carbs = Insights.total(dayMeals, "carbs") / ringGoals.optDouble("carbsGoal").coerceAtLeast(1.0)
                        val largeText = LocalDensity.current.fontScale > 1.3f
                        Column(Modifier.weight(1f).selectable(selected,role=Role.Tab,onClick={select(d)})
                            .semantics(mergeDescendants = true) {
                                contentDescription = d.format(DateTimeFormatter.ofPattern("M月d日 EEEE", java.util.Locale.CHINA))
                                stateDescription = "${if(entries.isNotEmpty()) "已有记录" else "无记录"}，用餐 ${dayMeals.size} 次，蛋白质 ${format(protein * 100)}%，碳水 ${format(carbs * 100)}%"
                            }.padding(vertical=6.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(5.dp)) {
                            Text(listOf("一","二","三","四","五","六","日")[i.toInt()],
                                Modifier.background(if(selected) Meals else Color.Transparent,CircleShape).padding(horizontal=5.dp,vertical=2.dp),
                                style=MaterialTheme.typography.labelSmall,color=if(selected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant)
                            if (largeText) Text(d.dayOfMonth.toString(), style=MaterialTheme.typography.bodySmall, color=if(selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
                            Box(Modifier.size(42.dp).clearAndSetSemantics {},contentAlignment=Alignment.Center) {
                                Ring(Modifier.fillMaxSize(), listOf(protein.toFloat(),carbs.toFloat(),dayMeals.size/4f),5f)
                                if (!largeText) Text(d.dayOfMonth.toString(),fontSize=9.sp,fontWeight=FontWeight.Bold,color=if(selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
        if(s.records.any {it.demo}) item {
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(MaterialTheme.colorScheme.surface.copy(alpha=.3f)).padding(12.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) {
                AppIcon(Glyph.Archive,MaterialTheme.colorScheme.primary,Modifier.size(20.dp))
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(2.dp)) {Text(if(preview) "正在体验示例数据" else "示例已隐藏，正在展示真实记录",style=MaterialTheme.typography.labelMedium.copy(fontWeight=FontWeight.SemiBold));Text(if(preview) "采用示例目标，不计入真实反馈" else "真实记录优先；示例仍可单独清除",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                SoftButton(onClick={runCatching {vm.clearDemo()}.onFailure {notify(it.message.orEmpty())}},shape=RoundedCornerShape(50),contentPadding=PaddingValues(horizontal=10.dp,vertical=5.dp),modifier=Modifier.height(32.dp)) {Text("清除",style=MaterialTheme.typography.labelMedium)}
            }
        }
        item { DailySummary(s.copy(profile=dayGoals), meals, body, date==LocalDate.now()) }
        item { Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ActionTile("记一餐", "拍照识别 · 手动记录", MaterialTheme.colorScheme.primary, Modifier.weight(1f)) { add(RecordType.MEAL) }
            ActionTile("记体重", "追踪趋势", Protein, Modifier.weight(1f)) { add(RecordType.BODY) }
        } }
        item { Panel {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { IconBadge(Glyph.Workout,Color(0xFF31B8C4),36.dp);Spacer(Modifier.width(10.dp));Text("健身记录", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f)); TextButton(onClick = { add(RecordType.WORKOUT) }) { Text("补记") } }
            if(date == LocalDate.now()) {
                val active = activeWorkout
                AppButton(onClick = { runCatching {
                    if(active == null) vm.startWorkout() else {
                        vm.endWorkout(active)
                        vm.snapshot.value.records.firstOrNull { it.id == active.id }?.let(edit)
                    }
                }.onFailure { notify(it.message ?: "保存失败") } }, Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF0D6E6E), contentColor = Color.White)) { Text(if(active == null) "开始训练" else "结束训练 · ${format((liveNow - active.date)/60)} 分钟") }
            } else if(workouts.isEmpty()) Text("这一天还没有训练记录", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if(workouts.isEmpty() && date==LocalDate.now()) Text("当天还没有训练记录",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            workouts.forEach { r -> RecordRow(r, { detail(r) }) }
        } }
        item { Panel {
            Text("营养目标", style = MaterialTheme.typography.titleLarge)
            listOf(Triple("蛋白质", "protein", Protein), Triple("碳水", "carbs", Carbs), Triple("脂肪", "fat", Fat)).forEach { (label, key, color) ->
                val value = Insights.total(meals, key); val goal = dayGoals.optDouble("${key}Goal")
                Column(verticalArrangement=Arrangement.spacedBy(7.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(label, style = MaterialTheme.typography.bodySmall); Text("${format(value)} / ${format(goal)} g", style = MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
                LinearProgressIndicator(progress = { (value / goal).toFloat().coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(4.dp)), color = color, trackColor = color.copy(alpha = .12f))
                }
            }
        } }
        item { Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text("饮食记录", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f)); TextButton(onClick = { history(true) }) { Text("照片") }; TextButton(onClick = { history(false) }) { Text("查看全部") } } }
        if(meals.isEmpty()) item { Panel { Empty("第一餐，从这里开始", "手动记录，或让 AI 帮你分析照片") } }
        listOf("早餐", "午餐", "晚餐", "加餐").forEach { kind ->
            val group = meals.filter { it.json.optString("kind") == kind }
            if(group.isNotEmpty()) item { Panel {
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {Text(kind,style=MaterialTheme.typography.titleMedium,color=MaterialTheme.colorScheme.primary);Text("${format(Insights.total(group,"calories"))} kcal",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                group.sortedByDescending {it.date}.forEach {r -> MealRow(r, { detail(r) }, { edit(r.copy()) }, { pendingDelete = r })}
            } }
        }
        val measurements = s.records.filter { it.type == RecordType.BODY && it.date.day() == date }
        if(measurements.isNotEmpty()) item { Panel { Text("身体测量", style = MaterialTheme.typography.titleLarge); measurements.forEach { RecordRow(it, { detail(it) }) } } }
        item { Panel(Modifier.clickable { coach("请根据我在 $date 的饮食和训练，给出可执行的下一步建议，不修改记录。") }) { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text("今日提示", style = MaterialTheme.typography.titleMedium); Text("问 AI", color = MaterialTheme.colorScheme.primary) }; Text(if(meals.isEmpty()) "先记下第一餐，让今天的进步有迹可循。" else "已记录 ${meals.size} 餐，蛋白质 ${format(Insights.total(meals,"protein"))} g。结合训练安排下一餐。", style = MaterialTheme.typography.bodyMedium) } }
        item { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(status, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant); TextButton(onClick = vm::sync) { Text("同步") } } }
    }
    }
    pendingDelete?.let { record -> DeleteConfirmationDialog("删除餐食？", "启用同步后，删除会同步到你的其他设备。", {pendingDelete=null}, {runCatching {vm.delete(record);pendingDelete=null;feedback(true);notify("记录已删除")}.onFailure {feedback(false);notify(it.message.orEmpty())}}) }
    if(datePicker) RecordCalendar(date, s.records, { datePicker = false }, select)
}
@Composable private fun DailySummary(s:Snapshot,meals:List<Record>,body:Record?,today:Boolean) {
    val calories=Insights.total(meals,"calories");val remaining=s.profile.optDouble("calorieGoal")-calories
    Panel {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
            AppIcon(Glyph.Target,MaterialTheme.colorScheme.primary,Modifier.size(19.dp))
            Spacer(Modifier.width(8.dp))
            Text(s.profile.optString("fitnessGoal","维持"),Modifier.weight(1f),style=MaterialTheme.typography.titleLarge,color=MaterialTheme.colorScheme.primary)
            Text("每日目标",Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.primary.copy(alpha=.12f)).padding(horizontal=10.dp,vertical=6.dp),style=MaterialTheme.typography.labelMedium.copy(fontWeight=FontWeight.SemiBold))
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val stacked=maxWidth<280.dp || LocalDensity.current.fontScale>1.3f
            val ring:@Composable ()->Unit={
                Box(Modifier.size(116.dp).semantics {contentDescription="今日营养圆环，用餐 ${meals.size} 次";stateDescription="蛋白质 ${format(Insights.total(meals,"protein"))} / ${format(s.profile.optDouble("proteinGoal"))} 克，碳水 ${format(Insights.total(meals,"carbs"))} / ${format(s.profile.optDouble("carbsGoal"))} 克"},contentAlignment=Alignment.Center) {
                    Ring(Modifier.fillMaxSize(),listOf((Insights.total(meals,"protein")/s.profile.optDouble("proteinGoal").coerceAtLeast(1.0)).toFloat(),(Insights.total(meals,"carbs")/s.profile.optDouble("carbsGoal").coerceAtLeast(1.0)).toFloat(),meals.size/4f),14f)
                    Column(horizontalAlignment=Alignment.CenterHorizontally) {
                        Text(meals.size.toString(),fontSize=20.sp,fontWeight=FontWeight.Bold,lineHeight=22.sp)
                        Text("餐",fontSize=11.sp,lineHeight=14.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            val metrics:@Composable ()->Unit={
                Column(verticalArrangement=Arrangement.spacedBy(10.dp)) {
                    Metric("蛋白质","${format(Insights.total(meals,"protein"))} / ${format(s.profile.optDouble("proteinGoal"))} g",Protein)
                    Metric("碳水","${format(Insights.total(meals,"carbs"))} / ${format(s.profile.optDouble("carbsGoal"))} g",Carbs)
                    Metric("体重",body?.let {"${format(it.json.optDouble("weight"))} kg"} ?: "暂无记录",MaterialTheme.colorScheme.primary)
                }
            }
            if(stacked) Column(verticalArrangement=Arrangement.spacedBy(16.dp)) {ring();metrics()}
            else Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(20.dp)) {ring();Box(Modifier.weight(1f)) {metrics()}}
        }
        HorizontalDivider(color=MaterialTheme.colorScheme.onSurface.copy(alpha=.08f))
        val calorieStatus=if(remaining>=0) "还差 ${format(remaining)} 千卡" else "超出 ${format(-remaining)} 千卡"
        androidx.compose.foundation.layout.FlowRow(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                Text(String.format(java.util.Locale.CHINA,"%,.0f",calories),style=AppTypography.number)
                Text("千卡",Modifier.padding(bottom=5.dp),style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(calorieStatus,Modifier.padding(top=14.dp),style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
@Composable fun Metric(label:String,value:String,color:Color) {
    Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(9.dp)) {
        Box(Modifier.size(9.dp).shadow(3.dp,CircleShape,ambientColor=color.copy(alpha=.3f),spotColor=color.copy(alpha=.3f)).background(color,CircleShape))
        Column(verticalArrangement=Arrangement.spacedBy(2.dp)) {
            Text(label,style=MaterialTheme.typography.bodyMedium.copy(fontWeight=FontWeight.SemiBold))
            Text(value,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
@Composable fun Ring(modifier: Modifier, values: List<Float>, thickness: Float) {
    val motion = rememberMotionEnabled()
    val animated = values.take(3).mapIndexed { index, value ->
        animateFloatAsState(if(value.isFinite()) value.coerceIn(0f,1f) else 0f,
            if(motion) spring(dampingRatio=.88f,stiffness=380f) else androidx.compose.animation.core.snap(),
            label="activity ring $index").value
    }
    Canvas(modifier) {
        val stroke = thickness.dp.toPx()
        animated.forEachIndexed { i, value ->
            val color = listOf(Protein,Carbs,Meals)[i]
            val inset = stroke/2+i*stroke; val diameter = size.minDimension-2*inset
            if(diameter>0) {
                val top = androidx.compose.ui.geometry.Offset(inset,inset); val dimensions = androidx.compose.ui.geometry.Size(diameter,diameter)
                drawArc(color.copy(alpha=.13f),-90f,360f,false,top,dimensions,style=Stroke(stroke))
                if(value>0) {
                    // Soft depth works on API 26 too, without another cached RenderEffect.
                    for (halo in 4 downTo 1) {
                        drawArc(Color.Black.copy(alpha=.025f),-90f,value*360f,false,
                            top+androidx.compose.ui.geometry.Offset(1.2.dp.toPx(),2.2.dp.toPx()),dimensions,
                            style=Stroke(stroke+halo*1.3.dp.toPx(),cap=StrokeCap.Round))
                        drawArc(color.copy(alpha=.04f),-90f,value*360f,false,
                            top+androidx.compose.ui.geometry.Offset(0f,1.dp.toPx()),dimensions,
                            style=Stroke(stroke+halo*1.8.dp.toPx(),cap=StrokeCap.Round))
                    }
                    rotate(-90f) {
                        drawArc(Brush.sweepGradient(listOf(color.copy(alpha=.72f),color,color.copy(alpha=.88f),color),center),
                            0f,value*360f,false,top,dimensions,style=Stroke(stroke,cap=StrokeCap.Round))
                    }
                }
            }
        }
    }
}
@Composable fun ActionTile(title:String,subtitle:String,tint:Color,modifier:Modifier,action:()->Unit) {
    Column(modifier.springClickable(role=androidx.compose.ui.semantics.Role.Button,onClick=action).cardMaterial(tint,22.dp).padding(17.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
            IconBadge(if(title=="记一餐") Glyph.Meal else Glyph.Weight,tint)
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(26.dp).background(tint.copy(alpha=.08f),CircleShape),contentAlignment=Alignment.Center) {AppIcon(Glyph.Plus,tint,Modifier.size(12.dp))}
        }
        Column(verticalArrangement=Arrangement.spacedBy(5.dp)) {
            Text(title,style=MaterialTheme.typography.titleLarge)
            Text(subtitle,style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
@Composable private fun MealRow(record:Record,open:()->Unit,edit:()->Unit,delete:()->Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
    Row(Modifier.fillMaxWidth().combinedClickable(onClick=open,onLongClick={menu=true}).padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(4.dp)) {
            Text(record.title,style=MaterialTheme.typography.bodyLarge.copy(fontWeight=FontWeight.Medium))
            if(record.demo) Text("示例",Modifier.background(MaterialTheme.colorScheme.primary.copy(alpha=.08f),RoundedCornerShape(50)).padding(horizontal=7.dp,vertical=2.dp),style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            Text("蛋白 ${format(record.json.optDouble("protein"))}g · 碳水 ${format(record.json.optDouble("carbs"))}g · 脂肪 ${format(record.json.optDouble("fat"))}g",style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column(horizontalAlignment=Alignment.End,verticalArrangement=Arrangement.spacedBy(4.dp)) {
            Text("${format(record.json.optDouble("calories"))} kcal",style=MaterialTheme.typography.bodySmall.copy(fontWeight=FontWeight.SemiBold))
            Text(java.time.Instant.ofEpochMilli((record.date*1000).toLong()).atZone(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofPattern("H:mm")),style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    DropdownMenu(menu,{menu=false}) {
        DropdownMenuItem(text={Text("编辑")},onClick={menu=false;edit()})
        DropdownMenuItem(text={Text("删除",color=MaterialTheme.colorScheme.error)},onClick={menu=false;delete()})
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
    }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "查看详情", tint = MaterialTheme.colorScheme.onSurfaceVariant)
} }
