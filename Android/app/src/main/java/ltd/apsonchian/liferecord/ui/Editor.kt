@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.platform.LocalContext
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.*
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.*
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalDensity
import android.graphics.BitmapFactory
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import org.json.*
import java.time.*
import java.time.format.DateTimeFormatter

/** Shared modal chrome. Intercept dismissal before hiding so a dirty editor stays visible. */
@Composable private fun FormFrame(title: String, dismiss: () -> Unit, actions: @Composable RowScope.() -> Unit,
    dismissEnabled: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    val keyboard = LocalSoftwareKeyboardController.current
    val keyboardVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    val close by rememberUpdatedState(dismiss)
    val canClose by rememberUpdatedState(dismissEnabled)
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = {
        if (it == SheetValue.Hidden) { if (canClose) close(); false } else true
    })
    ModalBottomSheet(onDismissRequest = { if (canClose) close() }, sheetState = sheet, containerColor = MaterialTheme.colorScheme.background) {
        Surface(Modifier.fillMaxWidth().fillMaxHeight(.96f), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.imePadding().widthIn(max = 760.dp)) {
                CenterAlignedTopAppBar(title = { Text(title, style = MaterialTheme.typography.titleLarge) },
                    navigationIcon = { TextButton(enabled = dismissEnabled, onClick = dismiss) { Text("取消") } },
                    actions = actions, windowInsets = WindowInsets(0, 0, 0, 0), colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent))
                content()
                if (keyboardVisible) TextButton(onClick = { keyboard?.hide() }, modifier = Modifier.align(Alignment.End)) { Text("收起键盘") }
            }
        }
    }
}
@Composable fun FullForm(title: String, dismiss: () -> Unit, actions: @Composable RowScope.() -> Unit = {},
    dismissEnabled: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    FormFrame(title, dismiss, actions, dismissEnabled) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
    }
}
@Composable fun LazyFullForm(title: String, dismiss: () -> Unit, actions: @Composable RowScope.() -> Unit = {}, content: LazyListScope.() -> Unit) {
    FormFrame(title, dismiss, actions) {
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
    }
}
@Composable internal fun DiscardChangesDialog(dismiss: () -> Unit, discard: () -> Unit) {
    AlertDialog(onDismissRequest = dismiss, title = { Text("放弃未保存的更改？") },
        text = { Text("已填写的内容和本次添加的照片将被清除。") },
        confirmButton = { TextButton(onClick = discard) { Text("放弃更改", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = dismiss) { Text("继续编辑") } })
}
@Composable fun TextFieldRow(label: String, value: String, change: (String) -> Unit, number: Boolean = false, lines: Int = 1) {
    Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {
        Text(label,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        BasicTextField(value,change,Modifier.fillMaxWidth().semantics {contentDescription=label}.clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surface).defaultMinSize(minHeight=44.dp).padding(12.dp),
            textStyle=MaterialTheme.typography.bodyLarge.copy(color=MaterialTheme.colorScheme.onSurface),cursorBrush=SolidColor(MaterialTheme.colorScheme.primary),
            keyboardOptions=KeyboardOptions(keyboardType=if(number && !label.contains("负数")) KeyboardType.Decimal else KeyboardType.Text),singleLine=lines==1,minLines=lines)
    }
}
@Composable fun SecretFieldRow(label:String,value:String,change:(String)->Unit) {
    Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {
        Text(label,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        BasicTextField(value,change,Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surface).defaultMinSize(minHeight=44.dp).padding(12.dp),
            textStyle=MaterialTheme.typography.bodyLarge.copy(color=MaterialTheme.colorScheme.onSurface),cursorBrush=SolidColor(MaterialTheme.colorScheme.primary),
            keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Password),visualTransformation=androidx.compose.ui.text.input.PasswordVisualTransformation(),singleLine=true)
    }
}
/** Native date and time pickers avoid format-dependent typing, like the iOS editor. */
@Composable fun DateTimeField(label: String, value: String, change: (String) -> Unit, optional: Boolean = false) {
    val context = LocalContext.current
    val choose = {
        val initial = runCatching { LocalDateTime.parse(value, DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")) }.getOrElse { LocalDateTime.now() }
        DatePickerDialog(context, { _, year, month, day ->
            TimePickerDialog(context, { _, hour, minute ->
                change(LocalDateTime.of(year, month + 1, day, hour, minute).format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")))
            }, initial.hour, initial.minute, true).show()
        }, initial.year, initial.monthValue - 1, initial.dayOfMonth).show()
        Unit
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SoftButton(onClick = choose, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp), contentPadding = PaddingValues(16.dp)) {
            Icon(Icons.Default.DateRange, null)
            Column(Modifier.weight(1f).padding(start = 12.dp), horizontalAlignment = Alignment.Start) {
                Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(value.ifBlank { "进行中 · 未设置结束时间" }, color = MaterialTheme.colorScheme.onSurface)
            }
        }
        if(optional && value.isNotBlank()) TextButton(onClick = { change("") }) { Text("清除结束时间，设为进行中") }
    }
}
fun Double.localText(): String = Instant.ofEpochMilli((this*1000).toLong()).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm"))
fun String.timestamp(): Double = LocalDateTime.parse(trim(), DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()/1000.0
@Composable fun RecordEditor(vm: AppViewModel, record: Record, dismiss: () -> Unit, notify: (String) -> Unit) {
    val r = rememberSaveable(record.id, saver = RecordSaver) {
        record.copy().apply {
            if(type in listOf(RecordType.MEAL, RecordType.BODY) && vm.snapshot.value.records.none { it.id == id }) {
                val time = LocalTime.now()
                json.put("date", date.day().epochAt(time))
                if(type == RecordType.MEAL) json.put("kind", when {
                    time.hour < 10 -> "早餐"
                    time.hour < 15 -> "午餐"
                    time.hour < 21 -> "晚餐"
                    else -> "加餐"
                })
            }
        }
    }
    val fields = rememberSaveable(r.id, saver = FieldMapSaver) { mutableStateMapOf<String,String>().apply { listOf("name","calories","protein","carbs","fat","fiber","weight","bodyFat","waist","note","portion","bodyPart").forEach { put(it, if(r.json.isNull(it)) "" else r.json.opt(it)?.toString().orEmpty()) } } }
    var date by rememberSaveable(r.id) { mutableStateOf(r.date.localText()) }
    var end by rememberSaveable(r.id) { mutableStateOf(if(r.json.isNull("endDate")) "" else r.json.optDouble("endDate").localText()) }
    var kind by rememberSaveable(r.id) { mutableStateOf(r.json.optString("kind", "午餐")) }
    var selectedParts by rememberSaveable(r.id) { mutableStateOf(WorkoutParts.of(r)) }
    var exercises by rememberSaveable(r.id, stateSaver = ExerciseListSaver) { mutableStateOf(r.json.optJSONArray("exercises")?.objects().orEmpty()) }
    var exEdit by rememberSaveable(r.id) { mutableStateOf<Int?>(null) }
    var images by rememberSaveable(r.id, stateSaver = draftPhotoSaver(vm.app.photos, r.id)) { mutableStateOf<List<ByteArray>>(emptyList()) }
    var input by rememberSaveable(r.id) { mutableStateOf(r.json.optString("inputText")) }
    var photoReading by remember { mutableStateOf(false) }
    var ai by rememberSaveable(r.id) { mutableStateOf(false) }; var aiBusy by remember { mutableStateOf(false) }; var error by rememberSaveable(r.id) { mutableStateOf("") }
    var customPart by rememberSaveable(r.id) { mutableStateOf("") }
    var showFavorites by rememberSaveable(r.id) { mutableStateOf(false) }
    var selectedFoodIDs by rememberSaveable(r.id, stateSaver = StringSetSaver) { mutableStateOf(setOf<String>()) }
    var favoritePhotos by rememberSaveable(r.id, stateSaver = draftPhotoSaver(vm.app.photos, r.id)) { mutableStateOf<List<ByteArray>>(emptyList()) }
    val existingPhotoCount = (r.json.optJSONArray("photoIDs")?.length() ?: 0) +
        (r.json.optJSONArray("localPhotoFiles")?.strings().orEmpty() - r.json.optJSONArray("uploadedPhotoFiles")?.strings().orEmpty().toSet()).size
    val photoLimit = (12 - existingPhotoCount).coerceAtLeast(0)
    var showExercises by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val s by vm.snapshot.collectAsState()
    val catalog by vm.bodyPartChoices.collectAsState()
    var modeName by rememberSaveable(r.id) { mutableStateOf(MealScanMode.MEAL.name) }
    val scanMode = MealScanMode.valueOf(modeName)
    var discard by remember { mutableStateOf(false) }
    val feedback = rememberActionFeedback()
    val imageSignature = remember(images) { images.map { it.contentHashCode() }.toString() }
    val signature = fields.toSortedMap().toString() + date + end + kind + selectedParts.toString() +
        JSONArray(exercises).toString() + input + imageSignature
    val initialSignature = rememberSaveable(r.id) { signature }
    val leave = { vm.app.photos.discardDraft(r.id); dismiss() }
    val requestDismiss = { if (!aiBusy && !photoReading) { if (signature != initialSignature) discard = true else leave() } }
    val build: () -> Record = {
        val edited = r.copy(); edited.json.put("date", if(date == r.date.localText()) r.date else date.timestamp())
        listOf("name","note","portion","bodyPart").forEach { edited.json.put(it, fields[it].orEmpty().trim()) }
        val numeric = when(r.type) { RecordType.MEAL, RecordType.FAVORITE -> listOf("calories","protein","carbs","fat","fiber"); RecordType.BODY -> listOf("weight","bodyFat","waist"); else -> emptyList() }
        numeric.forEach { key -> val text = fields[key].orEmpty(); if(text.isBlank() && key in listOf("bodyFat","waist")) edited.json.put(key, JSONObject.NULL) else edited.json.put(key, text.toDoubleOrNull() ?: error("请检查数字输入")) }
        if(r.type in listOf(RecordType.MEAL, RecordType.FAVORITE)) { edited.json.put("kind", kind); edited.json.put("inputText", input) }
        if(r.type == RecordType.WORKOUT) { edited.json.put("endDate", if(end.isBlank()) JSONObject.NULL else if(!r.json.isNull("endDate") && end == r.json.optDouble("endDate").localText()) r.json.optDouble("endDate") else end.timestamp()); if(r.json.has("bodyParts") || selectedParts != WorkoutParts.of(r)) edited.json.put("bodyParts", JSONArray(selectedParts)); edited.json.put("exercises", JSONArray(exercises)) }
        edited
    }
    FullForm("编辑${r.type.label}", requestDismiss, dismissEnabled = !aiBusy && !photoReading, actions = {
        TextButton(enabled = !aiBusy && !photoReading, onClick = { runCatching { vm.save(build(), images); feedback(true); leave(); notify("记录已保存") }.onFailure { feedback(false); error = it.message.orEmpty() } }) { Text("保存") }
    }) {
        if(error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error)
        if(r.demo) Text("这是示例记录，不会参与同步和真实趋势。", color = MaterialTheme.colorScheme.onSurfaceVariant)
        if(r.type in listOf(RecordType.MEAL, RecordType.FAVORITE)) {
            Panel {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { SoftButton(onClick = { ai = !ai }) { Text("AI 识别 / 修改") }; if(r.type == RecordType.MEAL) TextButton(onClick = { showFavorites = true }) { Text("常用餐食") } }
                PhotoInput(vm,images,maxCount=photoLimit,enabled=!aiBusy,change={images=it},notify={error=it},onReading={photoReading=it}) {open -> SoftButton(onClick=open) {Text(if(images.isEmpty()) "添加照片（可多选）" else "继续添加 · 已选 ${images.size} 张")} }
                if(images.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    images.forEachIndexed { index, bytes ->
                        Box {
                            PhotoBytes(bytes, Modifier.size(84.dp), maxDimension=256)
                            IconButton(onClick={images=images.filterIndexed {i,_ -> i!=index}}, modifier=Modifier.align(Alignment.TopEnd).size(44.dp).background(Color.Black.copy(alpha=.45f),RoundedCornerShape(22.dp))) {
                                Icon(Icons.Default.Close,"移除第 ${index+1} 张照片", tint=Color.White)
                            }
                        }
                    }
                }
                if(ai) {
                    Text("识别类型", style = MaterialTheme.typography.labelLarge)
                    ChoiceControl(MealScanMode.entries.map { it.name to it.title }, modeName, { modeName = it })
                    Text(when (scanMode) {
                        MealScanMode.MEAL -> "同一餐的多张照片会合并判断，避免重复计算。"
                        MealScanMode.NUTRITION_LABEL -> "请补充吃了多少克或多少份，方便换算包装上的营养数据。"
                        MealScanMode.INGREDIENTS -> "缺少营养表时会注明估算依据，请核对后保存。"
                    }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    TextFieldRow("描述食物、份量或修改要求", input, { input = it }, lines = 3)
                    AppButton(enabled = !aiBusy && !photoReading && (input.isNotBlank() || images.isNotEmpty()), onClick = {
                        aiBusy = true; scope.launch {
                            try {
                                val result = vm.nutrition(input, images, if(s.records.any { it.id == r.id }) build() else null, scanMode)
                                listOf("name","calories","protein","carbs","fat","fiber","note").forEach { key -> if(result.has(key)) fields[key] = result.get(key).toString() }
                                r.json.put("source", "AI 估算"); error = ""; feedback(true); notify("结果已填入，请核对后保存")
                            } catch(e: CancellationException) { throw e } catch(e: Exception) { feedback(false); error = e.message.orEmpty() } finally { aiBusy = false }
                        }
                    }, modifier=Modifier.fillMaxWidth()) { if(aiBusy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("生成营养草稿") }
                }
            }
            TextFieldRow("餐食名称", fields["name"].orEmpty(), { fields["name"] = it })
            if(r.type == RecordType.MEAL) ChoiceControl(kinds.map { it to it }, kind, { kind = it })
            else TextFieldRow("每份份量", fields["portion"].orEmpty(), { fields["portion"] = it })
            listOf("calories" to "热量 kcal", "protein" to "蛋白质 g", "carbs" to "碳水 g", "fat" to "脂肪 g", "fiber" to "膳食纤维 g").forEach { (key,label) -> TextFieldRow(label, fields[key].orEmpty(), { fields[key] = it }, true) }
            if(r.type == RecordType.MEAL && !ai) TextFieldRow("原始描述（可选）", input, { input = it }, lines = 2)
        }
        if(r.type == RecordType.BODY) {
            listOf("weight" to "体重 kg", "bodyFat" to "体脂率 %（可选）", "waist" to "腰围 cm（可选）").forEach { (key,label) -> TextFieldRow(label, fields[key].orEmpty(), { fields[key] = it }, true) }
        }
        if(r.type == RecordType.EXERCISE) {
            TextFieldRow("动作名称", fields["name"].orEmpty(), { fields["name"] = it })
            TextFieldRow("默认部位", fields["bodyPart"].orEmpty(), { fields["bodyPart"] = it })
        }
        if(r.type == RecordType.WORKOUT) {
            Text("训练部位", style = MaterialTheme.typography.titleMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { (catalog + selectedParts).distinct().forEach { part -> FilterChip(selected = part in selectedParts, onClick = { selectedParts = if(part in selectedParts) selectedParts - part else selectedParts + part }, label = { Text(part) }) } }
            Row(verticalAlignment = Alignment.CenterVertically) { OutlinedTextField(customPart, { customPart = it }, Modifier.weight(1f), label = { Text("自定义部位") }, singleLine = true); TextButton(onClick = { runCatching {val name=customPart.trim();require(WorkoutParts.valid(name)) {"部位名称无效"};if(name !in catalog) vm.addBodyPart(name);selectedParts=(selectedParts+name).distinct();customPart=""}.onFailure {error=it.message.orEmpty()} }) { Text("添加") } }
            DateTimeField("结束时间", end, { end = it }, optional = true)
            TextButton(onClick = { showExercises = !showExercises }) {
                Text("具体动作与组数（可选）", modifier = Modifier.weight(1f))
                Icon(if(showExercises) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown, if(showExercises) "收起动作" else "展开动作")
            }
            if(showExercises) Panel {
                exercises.forEachIndexed { index, ex -> Row(verticalAlignment = Alignment.CenterVertically) { TextButton(onClick = { exEdit = index }, Modifier.weight(1f)) { Text("${ex.optString("name")} · ${ex.optJSONArray("sets")?.length() ?: 0} 组") }; IconButton(onClick = { exercises = exercises.filterIndexed { i,_ -> i != index } }) { Icon(Icons.Default.Delete, "移除动作") } } }
                SoftButton(onClick = { exercises = exercises + JSONObject().put("name", "").put("sets", JSONArray()).put("bodyPart", selectedParts.firstOrNull() ?: "未分类"); exEdit = exercises.lastIndex }) { Text("添加动作") }
                val templates = s.records.filter { it.type == RecordType.EXERCISE }
                if(templates.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) { templates.forEach { template -> AssistChip(onClick = { exercises = exercises + JSONObject().put("name", template.title).put("bodyPart", template.json.optString("bodyPart", "未分类")).put("sets", JSONArray()) }, label = { Text(template.title) }) } }
            }
        }
        DateTimeField(if(r.type == RecordType.WORKOUT) "开始时间" else "记录时间", date, { date = it })
        TextFieldRow("备注", fields["note"].orEmpty(), { fields["note"] = it }, lines = 3)
        Spacer(Modifier.height(12.dp))
    }
    exEdit?.let { index -> if(index in exercises.indices) ExerciseEditor(exercises[index], { exEdit = null }) { ex -> exercises = exercises.mapIndexed { i,value -> if(i == index) ex else value }; exEdit = null } }
    if(showFavorites) FavoriteFoodPicker(s.records.filter { it.type == RecordType.FAVORITE }, selectedFoodIDs, { showFavorites=false }) { foods ->
        showFavorites=false
        scope.launch {
            aiBusy=true
            try {
                val added=withContext(Dispatchers.IO) { foods.flatMap { it.json.optJSONArray("localPhotoFiles")?.strings().orEmpty() }.mapNotNull { runCatching { vm.app.photos.local(it) }.getOrNull() } }
                val manual=images.filter { photo -> favoritePhotos.none { it.contentEquals(photo) } }
                val combined=(manual+added).fold(emptyList<ByteArray>()) { all,photo -> if(all.any {it.contentEquals(photo)}) all else all+photo }
                listOf("calories","protein","carbs","fat","fiber").forEach { key -> fields[key]=foods.sumOf {it.json.optDouble(key,0.0)}.toString() }
                fields["name"]=foods.joinToString("、") {it.title}
                fields["note"]=foods.joinToString("\n") {listOf(it.title,it.json.optString("portion","1 份"),it.json.optString("note")).filter {v -> v.isNotBlank()}.joinToString(" · ")}
                selectedFoodIDs=foods.map {it.id}.toSet();favoritePhotos=added;images=combined.take(photoLimit)
                error=if(combined.size>photoLimit) "营养已全部填入；照片最多再添加 $photoLimit 张。" else ""
                r.json.put("source","手动");input="";showFavorites=false
            } finally {aiBusy=false}
        }
    }
    if (discard) DiscardChangesDialog({ discard = false }, { discard = false; leave() })
}
@Composable fun ExerciseEditor(original: JSONObject, dismiss: () -> Unit, save: (JSONObject) -> Unit) {
    var name by rememberSaveable { mutableStateOf(original.optString("name")) }; var part by rememberSaveable { mutableStateOf(original.optString("bodyPart", "未分类")) }
    var rows by rememberSaveable(stateSaver = SetRowsSaver) { mutableStateOf(original.getJSONArray("sets").objects().map { s -> listOf("reps","weight","durationSeconds").map { if(s.isNull(it)) "" else s.opt(it)?.toString().orEmpty() } }) }
    var error by rememberSaveable { mutableStateOf("") }
    var discard by remember { mutableStateOf(false) }
    val initial = rememberSaveable { name + part + rows.toString() }
    val close = { if (name + part + rows.toString() != initial) discard = true else dismiss() }
    FullForm("动作与逐组数据", close, { TextButton(onClick = {
        runCatching {
            val sets = rows.map { values -> JSONObject().apply { listOf("reps","weight","durationSeconds").forEachIndexed { i,key -> if(values[i].isBlank()) put(key, JSONObject.NULL) else if(key == "weight") put(key, values[i].toDouble()) else put(key, values[i].toInt()) } } }
            val ex = JSONObject().put("name",name.trim()).put("bodyPart",part.trim().ifBlank { "未分类" }).put("sets",JSONArray(sets))
            Validation.record(Record.create(RecordType.WORKOUT).apply { json.put("exercises",JSONArray().put(ex)) }); save(ex)
        }.onFailure { error = it.message ?: "请检查数据" }
    }) { Text("完成") } }) {
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
        TextFieldRow("动作",name,{name=it}); TextFieldRow("部位",part,{part=it})
        rows.forEachIndexed { i,values -> Panel {
            Row(verticalAlignment=Alignment.CenterVertically) { Text("第 ${i+1} 组",modifier=Modifier.weight(1f)); IconButton(onClick={rows=rows.filterIndexed { idx,_ -> idx != i }}) { Icon(Icons.Default.Delete,"删除组") } }
            listOf("次数","重量 kg","时长 秒").forEachIndexed { col,label -> TextFieldRow("$label（可选）",values[col],{v -> rows=rows.mapIndexed { idx,row -> if(idx==i) row.mapIndexed { j,old -> if(j==col) v else old } else row }},true) }
        } }
        SoftButton(onClick={rows=rows+listOf(listOf("","",""))},enabled=rows.size<100) { Text("添加一组") }
    }
    if (discard) DiscardChangesDialog({ discard = false }, dismiss)
}
@Composable fun RecordDetail(vm: AppViewModel, r: Record, dismiss: () -> Unit, edit: () -> Unit, notify: (String) -> Unit) {
    var delete by remember { mutableStateOf(false) }
    FullForm(r.type.label,dismiss,{ TextButton(onClick=edit) { Text("编辑") } }) {
        Text(r.title,style=MaterialTheme.typography.headlineMedium); Text(r.date.localText(),color=MaterialTheme.colorScheme.onSurfaceVariant)
        if(r.type in listOf(RecordType.MEAL,RecordType.FAVORITE)) {
            Panel { listOf("calories" to "热量 kcal","protein" to "蛋白质 g","carbs" to "碳水 g","fat" to "脂肪 g","fiber" to "膳食纤维 g").forEach { (key,label) -> Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) { Text(label); Text(format(r.json.optDouble(key))) } } }
            val locals=r.json.optJSONArray("localPhotoFiles")?.strings().orEmpty()
            val remotes=r.json.optJSONArray("photoIDs")?.strings().orEmpty().drop(r.json.optJSONArray("uploadedPhotoFiles")?.length() ?: 0)
            (locals.map { it to true }+remotes.map { it to false }).forEach { (id,local) -> PhotoRecord(vm,r,id,local) }
            Panel { Text("原始描述",style=MaterialTheme.typography.titleMedium); Text(r.json.optString("inputText").ifBlank { "这条记录没有保存原始描述。" }); Text("来源：${r.json.optString("source","手动")}",color=MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        if(r.type == RecordType.BODY) Panel { listOf("bodyFat" to "体脂率 %","waist" to "腰围 cm").forEach { (key,label) -> if(!r.json.isNull(key) && r.json.has(key)) Text("$label · ${format(r.json.optDouble(key))}") }; if(r.json.isNull("bodyFat") && r.json.isNull("waist")) Text("未填写体脂与腰围") }
        if(r.type == RecordType.WORKOUT) {
            Panel { Text(if(r.json.isNull("endDate")) "进行中" else "结束：${r.json.optDouble("endDate").localText()}"); r.json.optJSONArray("exercises")?.objects()?.forEach { ex -> Text(ex.optString("name"),style=MaterialTheme.typography.titleMedium); ex.getJSONArray("sets").objects().forEachIndexed { i,s -> Text("第 ${i+1} 组 · " + listOf("reps" to "次","weight" to "kg","durationSeconds" to "秒").mapNotNull { (key,unit) -> if(s.isNull(key)) null else "${format(s.getDouble(key))} $unit" }.joinToString(" · ").ifBlank { "未填写数值" }) } } }
        }
        if(r.json.optString("note").isNotBlank()) Panel { Text("备注",style=MaterialTheme.typography.titleMedium); Text(r.json.getString("note")) }
        Insights.quality(r).forEach { Text(it,color=MaterialTheme.colorScheme.error) }
        SoftButton(onClick={delete=true},modifier=Modifier.fillMaxWidth()) { Text("删除这条记录",color=MaterialTheme.colorScheme.error) }
    }
    if(delete) DeleteConfirmationDialog(
        title = "删除${r.type.label}？",
        message = "启用同步后，删除会同步到你的其他设备。",
        onDismiss = { delete = false },
        onConfirm = { runCatching { vm.delete(r); delete = false; dismiss(); notify("记录已删除") }.onFailure { notify(it.message.orEmpty()) } }
    )
}
@Composable fun PhotoBytes(bytes: ByteArray, modifier: Modifier = Modifier, contentScale: androidx.compose.ui.layout.ContentScale = androidx.compose.ui.layout.ContentScale.Crop, maxDimension: Int = 1024) {
    val bitmap = remember(bytes,maxDimension) {
        val bounds=BitmapFactory.Options().apply {inJustDecodeBounds=true}
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
        val options=BitmapFactory.Options().apply {
            inSampleSize=1
            while(maxOf(bounds.outWidth,bounds.outHeight)/inSampleSize > maxDimension.coerceAtLeast(64)) inSampleSize*=2
        }
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,options)?.asImageBitmap()
    }
    bitmap?.let { Image(it,"照片",modifier.clip(RoundedCornerShape(16.dp)),contentScale=contentScale) }
}
@Composable fun PhotoRecord(vm: AppViewModel,r:Record,id:String,local:Boolean) {
    var bytes by remember(id) { mutableStateOf<ByteArray?>(null) }; var error by remember { mutableStateOf("") }; var retry by remember { mutableIntStateOf(0) }; var full by remember { mutableStateOf(false) }
    LaunchedEffect(id,retry) { try { bytes=vm.photo(r,id,local); error="" } catch(e:Exception) { error=e.message.orEmpty() } }
    bytes?.let { data -> Box(Modifier.fillMaxWidth().height(220.dp).clickable { full=true }) { PhotoBytes(data,Modifier.fillMaxSize()) } } ?: if(error.isBlank()) CircularProgressIndicator() else TextButton(onClick={retry++}) { Text("照片加载失败，点此重试") }
    if(full) {
        val photos = recordGallery(vm, r)
        val key = "${if (local) "local" else "remote"}:$id"
        PhotoGallery(vm, photos, photos.indexOfFirst { it.key == key }.coerceAtLeast(0)) { full = false }
    }
}

@Composable fun FavoriteFoodPicker(foods: List<Record>, initialSelection: Set<String> = emptySet(), dismiss: () -> Unit, select: (List<Record>) -> Unit) {
    var selected by remember { mutableStateOf(initialSelection) }
    val chosen=foods.filter {it.id in selected}
    FullForm("选择常用餐食",dismiss,actions={
        TextButton(enabled=chosen.isNotEmpty(),onClick={select(chosen)}) {Text("填入 ${chosen.size} 项")}
    }) {
        if(foods.isEmpty()) Empty("还没有常用餐食","在设置中保存固定份量和营养。")
        else {
            Text("已选 ${chosen.size} 项 · 各 1 份 · ${format(chosen.sumOf {it.json.optDouble("calories",0.0)})} kcal",style=MaterialTheme.typography.bodyMedium)
            foods.forEach {food ->
                Surface(shape=RoundedCornerShape(16.dp),color=MaterialTheme.colorScheme.surface) {
                    Row(Modifier.fillMaxWidth().toggleable(value=food.id in selected,role=androidx.compose.ui.semantics.Role.Checkbox,onValueChange={checked -> selected=if(checked) selected+food.id else selected-food.id}).padding(16.dp),verticalAlignment=Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(food.title,style=MaterialTheme.typography.titleMedium)
                            Text("${food.json.optString("portion","1 份")} · ${format(food.json.optDouble("calories",0.0))} kcal",color=MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Checkbox(checked=food.id in selected,onCheckedChange=null)
                    }
                }
            }
        }
    }
}
