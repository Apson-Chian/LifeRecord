@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package ltd.apsonchian.liferecord.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.*
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalDensity
import android.graphics.BitmapFactory
import android.os.Build
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import org.json.*
import java.time.*
import java.time.format.DateTimeFormatter

@Composable fun FullForm(title: String, dismiss: () -> Unit, actions: @Composable RowScope.() -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    val keyboard = LocalSoftwareKeyboardController.current
    val keyboardVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    ModalBottomSheet(onDismissRequest = dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = MaterialTheme.colorScheme.background) {
        Surface(Modifier.fillMaxWidth().fillMaxHeight(.96f), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.imePadding().widthIn(max = 760.dp)) {
                CenterAlignedTopAppBar(title = { Text(title, style = MaterialTheme.typography.titleLarge) }, navigationIcon = { TextButton(onClick = dismiss) { Text("取消") } }, actions = actions, colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent))
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
                if(keyboardVisible) TextButton(onClick = { keyboard?.hide() }, modifier = Modifier.align(Alignment.End)) { Text("收起键盘") }
            }
        }
    }
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
    val r = remember(record.id) {
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
    val fields = remember { mutableStateMapOf<String,String>().apply { listOf("name","calories","protein","carbs","fat","fiber","weight","bodyFat","waist","note","portion","bodyPart").forEach { put(it, if(r.json.isNull(it)) "" else r.json.opt(it)?.toString().orEmpty()) } } }
    var date by remember { mutableStateOf(r.date.localText()) }
    var end by remember { mutableStateOf(if(r.json.isNull("endDate")) "" else r.json.optDouble("endDate").localText()) }
    var kind by remember { mutableStateOf(r.json.optString("kind", "午餐")) }
    var selectedParts by remember { mutableStateOf(WorkoutParts.of(r)) }
    var exercises by remember { mutableStateOf(r.json.optJSONArray("exercises")?.objects().orEmpty()) }
    var exEdit by remember { mutableStateOf<Int?>(null) }
    var images by remember { mutableStateOf<List<ByteArray>>(emptyList()) }
    var input by remember { mutableStateOf(r.json.optString("inputText")) }
    var ai by remember { mutableStateOf(false) }; var aiBusy by remember { mutableStateOf(false) }; var error by remember { mutableStateOf("") }
    var customPart by remember { mutableStateOf("") }
    var showFavorites by remember { mutableStateOf(false) }
    var selectedFoodIDs by remember { mutableStateOf(setOf<String>()) }
    var favoritePhotos by remember { mutableStateOf<List<ByteArray>>(emptyList()) }
    val existingPhotoCount = (r.json.optJSONArray("photoIDs")?.length() ?: 0) +
        (r.json.optJSONArray("localPhotoFiles")?.strings().orEmpty() - r.json.optJSONArray("uploadedPhotoFiles")?.strings().orEmpty().toSet()).size
    val photoLimit = (12 - existingPhotoCount).coerceAtLeast(0)
    var showExercises by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val s by vm.snapshot.collectAsState()
    val catalog by vm.bodyPartChoices.collectAsState()
    val build: () -> Record = {
        val edited = r.copy(); edited.json.put("date", if(date == r.date.localText()) r.date else date.timestamp())
        listOf("name","note","portion","bodyPart").forEach { edited.json.put(it, fields[it].orEmpty().trim()) }
        val numeric = when(r.type) { RecordType.MEAL, RecordType.FAVORITE -> listOf("calories","protein","carbs","fat","fiber"); RecordType.BODY -> listOf("weight","bodyFat","waist"); else -> emptyList() }
        numeric.forEach { key -> val text = fields[key].orEmpty(); if(text.isBlank() && key in listOf("bodyFat","waist")) edited.json.put(key, JSONObject.NULL) else edited.json.put(key, text.toDoubleOrNull() ?: error("请检查数字输入")) }
        if(r.type in listOf(RecordType.MEAL, RecordType.FAVORITE)) { edited.json.put("kind", kind); edited.json.put("inputText", input) }
        if(r.type == RecordType.WORKOUT) { edited.json.put("endDate", if(end.isBlank()) JSONObject.NULL else if(!r.json.isNull("endDate") && end == r.json.optDouble("endDate").localText()) r.json.optDouble("endDate") else end.timestamp()); if(r.json.has("bodyParts") || selectedParts != WorkoutParts.of(r)) edited.json.put("bodyParts", JSONArray(selectedParts)); edited.json.put("exercises", JSONArray(exercises)) }
        edited
    }
    FullForm("编辑${r.type.label}", dismiss, actions = {
        TextButton(enabled = !aiBusy, onClick = { runCatching { vm.save(build(), images); dismiss(); notify("记录已保存") }.onFailure { error = it.message.orEmpty() } }) { Text("保存") }
    }) {
        if(error.isNotBlank()) Text(error, color = MaterialTheme.colorScheme.error)
        if(r.demo) Text("这是示例记录，不会参与同步和真实趋势。", color = MaterialTheme.colorScheme.onSurfaceVariant)
        if(r.type in listOf(RecordType.MEAL, RecordType.FAVORITE)) {
            Panel {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { SoftButton(onClick = { ai = !ai }) { Text("AI 识别 / 修改") }; if(r.type == RecordType.MEAL) TextButton(onClick = { showFavorites = true }) { Text("常用餐食") } }
                PhotoInput(vm,images,maxCount=photoLimit,enabled=!aiBusy,change={images=it},notify={error=it}) {open -> SoftButton(onClick=open) {Text(if(images.isEmpty()) "添加照片（可多选）" else "继续添加 · 已选 ${images.size} 张")} }
                if(images.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    images.forEachIndexed { index, bytes ->
                        Box {
                            PhotoBytes(bytes, Modifier.size(84.dp))
                            IconButton(onClick={images=images.filterIndexed {i,_ -> i!=index}}, modifier=Modifier.align(Alignment.TopEnd).size(44.dp).background(Color.Black.copy(alpha=.45f),RoundedCornerShape(22.dp))) {
                                Icon(Icons.Default.Close,"移除第 ${index+1} 张照片", tint=Color.White)
                            }
                        }
                    }
                }
                if(ai) {
                    TextFieldRow("描述食物、份量或修改要求", input, { input = it }, lines = 3)
                    AppButton(enabled = !aiBusy && (input.isNotBlank() || images.isNotEmpty()), onClick = {
                        aiBusy = true; scope.launch {
                            try {
                                val result = vm.nutrition(input, images, if(s.records.any { it.id == r.id }) build() else null)
                                listOf("name","calories","protein","carbs","fat","fiber","note").forEach { key -> if(result.has(key)) fields[key] = result.get(key).toString() }
                                r.json.put("source", "AI 估算"); error = ""; notify("结果已填入，请核对后保存")
                            } catch(e: Exception) { error = e.message.orEmpty() } finally { aiBusy = false }
                        }
                    }, modifier=Modifier.fillMaxWidth()) { if(aiBusy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("生成营养草稿") }
                }
            }
            TextFieldRow("餐食名称", fields["name"].orEmpty(), { fields["name"] = it })
            if(r.type == RecordType.MEAL) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { kinds.forEach { FilterChip(selected = kind == it, onClick = { kind = it }, label = { Text(it) }) } }
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
}
@Composable fun ExerciseEditor(original: JSONObject, dismiss: () -> Unit, save: (JSONObject) -> Unit) {
    var name by remember { mutableStateOf(original.optString("name")) }; var part by remember { mutableStateOf(original.optString("bodyPart", "未分类")) }
    var rows by remember { mutableStateOf(original.getJSONArray("sets").objects().map { s -> listOf("reps","weight","durationSeconds").map { if(s.isNull(it)) "" else s.opt(it)?.toString().orEmpty() } }) }
    var error by remember { mutableStateOf("") }
    FullForm("动作与逐组数据", dismiss, { TextButton(onClick = {
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
@Composable fun PhotoBytes(bytes: ByteArray, modifier: Modifier = Modifier, contentScale: androidx.compose.ui.layout.ContentScale = androidx.compose.ui.layout.ContentScale.Crop) {
    val bitmap = remember(bytes) { BitmapFactory.decodeByteArray(bytes,0,bytes.size)?.asImageBitmap() }
    bitmap?.let { Image(it,"照片",modifier.clip(RoundedCornerShape(16.dp)),contentScale=contentScale) }
}
@Composable fun PhotoRecord(vm: AppViewModel,r:Record,id:String,local:Boolean) {
    var bytes by remember(id) { mutableStateOf<ByteArray?>(null) }; var error by remember { mutableStateOf("") }; var retry by remember { mutableIntStateOf(0) }; var full by remember { mutableStateOf(false) }
    LaunchedEffect(id,retry) { try { bytes=vm.photo(r,id,local); error="" } catch(e:Exception) { error=e.message.orEmpty() } }
    bytes?.let { data -> Box(Modifier.fillMaxWidth().height(220.dp).clickable { full=true }) { PhotoBytes(data,Modifier.fillMaxSize()) } } ?: if(error.isBlank()) CircularProgressIndicator() else TextButton(onClick={retry++}) { Text("照片加载失败，点此重试") }
    if(full) bytes?.let { PhotoViewer(vm,it) { full=false } }
}

@Composable fun PhotoViewer(vm:AppViewModel,data:ByteArray,dismiss:()->Unit) {
    val context=LocalContext.current
    val scope=rememberCoroutineScope()
    var saving by remember { mutableStateOf(false) };var notice by remember { mutableStateOf("") }
    val document=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("image/jpeg")) { uri ->
        if(uri!=null) scope.launch {
            saving=true
            try { withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(data) } ?: error("无法写入照片") };notice="照片已保存" }
            catch(e:Exception) { notice="保存失败：${e.message.orEmpty()}" } finally { saving=false }
        }
    }
    Dialog(onDismissRequest=dismiss,properties=DialogProperties(usePlatformDefaultWidth=false,decorFitsSystemWindows=false)) {
        var scale by remember { mutableFloatStateOf(1f) };var offset by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) };var swipe by remember { mutableFloatStateOf(0f) }
        val threshold=with(LocalDensity.current) { 96.dp.toPx() }
        Box(Modifier.fillMaxSize().background(Color.Black).testTag("photo-viewer")
            .transformable(rememberTransformableState { zoom,pan,_ -> scale=(scale*zoom).coerceIn(1f,5f);offset=if(scale>1) offset+pan else androidx.compose.ui.geometry.Offset.Zero },canPan={scale>1f})
            .pointerInput(scale) { detectTapGestures(onDoubleTap={scale=if(scale>1) 1f else 2f;offset=androidx.compose.ui.geometry.Offset.Zero}) }
            .pointerInput(scale) { if(scale<=1f) detectVerticalDragGestures(onVerticalDrag={change,delta -> change.consume();swipe=(swipe+delta).coerceAtLeast(0f)},onDragEnd={if(swipe>threshold) dismiss() else swipe=0f},onDragCancel={swipe=0f}) }) {
            PhotoBytes(data,Modifier.fillMaxSize().graphicsLayer { scaleX=scale;scaleY=scale;translationX=offset.x;translationY=offset.y+swipe },androidx.compose.ui.layout.ContentScale.Fit)
            Row(Modifier.align(Alignment.TopCenter).fillMaxWidth().statusBarsPadding().padding(horizontal=12.dp),verticalAlignment=Alignment.CenterVertically) {
                IconButton(onClick=dismiss) { Icon(Icons.Default.Close,"关闭照片",tint=Color.White) }
                Spacer(Modifier.weight(1f))
                TextButton(enabled=!saving,onClick={
                    if(Build.VERSION.SDK_INT<29) document.launch("LifeRecord-${System.currentTimeMillis()}.jpg") else scope.launch {
                        saving=true
                        try { withContext(Dispatchers.IO) { vm.app.photos.saveToGallery(data) };notice="已保存到系统相册" }
                        catch(e:Exception) { notice="保存失败：${e.message.orEmpty()}" } finally { saving=false }
                    }
                }) { Text(if(saving) "保存中…" else "保存到相册",color=Color.White) }
            }
            if(notice.isNotBlank()) Text(notice,color=Color.White,modifier=Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(24.dp))
        }
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
