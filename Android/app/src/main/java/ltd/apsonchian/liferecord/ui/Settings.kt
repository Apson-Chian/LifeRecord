@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package ltd.apsonchian.liferecord.ui

import android.Manifest
import android.app.TimePickerDialog
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.*
import org.json.*
import java.time.LocalTime
import android.content.Intent
import android.net.Uri

@Composable fun Settings(vm:AppViewModel,s:Snapshot,notify:(String)->Unit) {
    var page by rememberSaveable { mutableStateOf("") }; var clear by remember { mutableStateOf(false) }
    val status by vm.status.collectAsState(); val context=LocalContext.current; val scope=rememberCoroutineScope()
    val export=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri -> if(uri!=null) scope.launch {
        runCatching { val text=vm.export(); withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) } ?: error("无法写入文件") } }.onSuccess { notify("记录已导出") }.onFailure { notify(it.message.orEmpty()) }
    } }
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp,20.dp,16.dp,glassPageBottomPadding()),verticalArrangement=Arrangement.spacedBy(18.dp)) {
        item { PageTitle("设置","偏好与个人目标") }
        item { Panel {
            Text(s.profile.optString("displayName").ifBlank { "我的档案" },style=MaterialTheme.typography.titleLarge)
            Text("${s.profile.optString("fitnessGoal")} · 目标 ${format(s.profile.optDouble("targetWeight"))} kg",color=MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick={page="profile"},modifier=Modifier.fillMaxWidth()) { Text("编辑档案与目标") }
        } }
        item { Panel {
            SettingsRow("AI 接口","选择模型、图片能力与写入权限") { page="ai" }
            SettingsRow("App 与浏览器同步",status) { page="sync" }
        } }
        item { Panel {
            SettingsRow("常用餐食","保存固定份量和营养") { page="favorites" }
            SettingsRow("我的动作库","常用动作与默认训练部位") { page="exercises" }
            SettingsRow("漏记提醒","按需提醒餐食、测量和训练") { page="reminders" }
        } }
        item { Panel {
            SettingsRow("导出记录 JSON","包括照片编号；本机照片和对话不包含在导出中") { export.launch("LifeRecord-${java.time.LocalDate.now()}.json") }
            SettingsRow("重看引导","了解记录、AI 与私有同步") { vm.onboarding.value=true }
            SettingsRow("清除示例数据","仅清除带有示例标记的记录") { clear=true }
        } }
        item { Text("LifeRecord · Android 1.1\n记录保存在本机，密钥由 Android Keystore 加密。使用 AI 时，记录上下文会发送至你选择的接口。同步使用原有私有服务器。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    when(page) {
        "profile" -> ProfileForm(vm,s.profile,{page=""},notify)
        "ai" -> AISettings(vm,{page=""},notify)
        "sync" -> SyncSettings(vm,{page=""},notify)
        "favorites" -> Library(vm,RecordType.FAVORITE,{page=""},notify)
        "exercises" -> Library(vm,RecordType.EXERCISE,{page=""},notify)
        "reminders" -> Reminders(vm,{page=""},notify)
    }
    if(clear) AlertDialog(onDismissRequest={clear=false},title={Text("清除示例数据？")},text={Text("你自己记录和同步的内容会保留。")},confirmButton={TextButton(onClick={vm.clearDemo();clear=false;notify("示例数据已清除")}) { Text("清除") }},dismissButton={TextButton(onClick={clear=false}) { Text("取消") }})
}
@Composable fun SettingsRow(title:String,subtitle:String,onClick:()->Unit) { Row(Modifier.fillMaxWidth().clickable(onClick=onClick).padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(title,style=MaterialTheme.typography.titleMedium); Spacer(Modifier.height(4.dp)); Text(subtitle,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }; Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight,title) } }
@Composable fun Toggle(title:String,subtitle:String="",checked:Boolean,onChange:(Boolean)->Unit) { Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(title); if(subtitle.isNotBlank()) Text(subtitle,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }; Switch(checked,onChange) } }
@Composable fun ProfileForm(vm:AppViewModel,original:JSONObject,dismiss:()->Unit,notify:(String)->Unit) {
    val fields=remember { mutableStateMapOf<String,String>().apply { original.keys().forEach { put(it,original.opt(it)?.toString().orEmpty()) } } }
    var error by remember { mutableStateOf("") }
    FullForm("档案与每日目标",dismiss,{TextButton(onClick={runCatching {
        val p=original.copy(); fields.forEach { (key,value) -> if(key in listOf("displayName","fitnessGoal","id")) p.put(key,value) else if(key!="updatedAt") p.put(key,value.toDouble()) }; vm.saveProfile(p); dismiss(); notify("目标已保存")
    }.onFailure { error=it.message.orEmpty() }}) { Text("保存") }}) {
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
        TextFieldRow("称呼",fields["displayName"].orEmpty(),{fields["displayName"]=it})
        FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) { listOf("增肌","减脂","维持").forEach { goal -> FilterChip(fields["fitnessGoal"]==goal,{fields["fitnessGoal"]=goal},label={Text(goal)}) } }
        listOf("height" to "身高 cm","baselineWeight" to "起始体重 kg","targetWeight" to "目标体重 kg","weeklyWeightTarget" to "每周变化 kg（减重填负数）","calorieGoal" to "热量目标 kcal","proteinGoal" to "蛋白质目标 g","carbsGoal" to "碳水目标 g","fatGoal" to "脂肪目标 g").forEach { (key,label) -> TextFieldRow(label,fields[key].orEmpty(),{fields[key]=it},true) }
    }
}
@Composable fun AISettings(vm:AppViewModel,dismiss:()->Unit,notify:(String)->Unit) {
    val current by vm.config.collectAsState()
    var provider by remember { mutableStateOf(current.getString("provider")) }
    val fields=remember { mutableStateMapOf<String,String>().apply { listOf("endpoint","model","auth","header","maxPhotos","temperature","maxTokens","instructions").forEach { put(it,current.opt(it)?.toString().orEmpty()) } } }
    var vision by remember { mutableStateOf(current.optBoolean("vision")) }; var canWrite by remember { mutableStateOf(current.optBoolean("canWrite")) }
    var key by remember { mutableStateOf("") }; var keyTouched by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf(false) }; var error by remember { mutableStateOf("") }
    val scope=rememberCoroutineScope()
    val context=LocalContext.current
    val officialDeepSeek=AIAuthentication.officialDeepSeek(fields["endpoint"].orEmpty())
    val save:()->Unit={
        val c=JSONObject().put("provider",provider).put("vision",vision).put("canWrite",canWrite)
        fields.forEach { (name,value) -> c.put(name,when(name) { "temperature" -> value.toDouble(); "maxPhotos","maxTokens" -> value.toInt(); else -> value }) }
        vm.saveConfig(c,if(keyTouched) key else null)
    }
    FullForm("AI 接口",dismiss,{TextButton(enabled=!busy,onClick={runCatching { save();dismiss();notify("AI 设置已保存") }.onFailure { error=it.message.orEmpty() }}) { Text("保存") }}) {
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
        FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) { providers.forEach { p -> FilterChip(provider==p,onClick={
            if(provider!=p) { provider=p; val c=providerConfig(p); fields.keys.toList().forEach { fields[it]=c.opt(it)?.toString().orEmpty() }; vision=c.optBoolean("vision"); key="";keyTouched=false }
        },label={Text(p)}) } }
        TextFieldRow("接口地址（HTTPS）",fields["endpoint"].orEmpty(),{fields["endpoint"]=it});TextFieldRow("模型名",fields["model"].orEmpty(),{fields["model"]=it})
        if(officialDeepSeek) {
            Text("DeepSeek 官方接口使用 Authorization: Bearer；更新会自动纠正旧认证配置。请使用开放平台创建的完整 API Key。deepseek-flash 支持图片；已有配置可开启下方的“支持图片”。",style=MaterialTheme.typography.bodySmall)
            TextButton(onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://platform.deepseek.com/api_keys")))}) { Text("打开 DeepSeek API Key 页面") }
        } else FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) { listOf("Bearer","api-key","自定义").forEach { auth -> FilterChip(fields["auth"]==auth,{fields["auth"]=auth},label={Text(auth)}) } }
        if(!officialDeepSeek && fields["auth"]=="自定义") TextFieldRow("认证请求头",fields["header"].orEmpty(),{fields["header"]=it})
        OutlinedTextField(key,{key=it;keyTouched=true},Modifier.fillMaxWidth(),label={Text("API Key（留空保留已有密钥）")},visualTransformation=PasswordVisualTransformation(),singleLine=true)
        Text("每个服务商的密钥分别保存。切换不会把其他服务商的密钥发到当前接口。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Toggle("支持图片","需要模型本身支持视觉输入",vision,{vision=it})
        listOf("maxPhotos" to "最多照片数（1–12）","temperature" to "Temperature（0–2）","maxTokens" to "最大输出 Token（256–4096）").forEach { (name,label) -> TextFieldRow(label,fields[name].orEmpty(),{fields[name]=it},true) }
        TextFieldRow("自定义指令",fields["instructions"].orEmpty(),{fields["instructions"]=it},lines=3)
        Toggle("允许 AI 提出写入操作","每次操作均需在教练中复核保存",canWrite,{canWrite=it})
        Button(enabled=!busy,onClick={runCatching { save() }.onSuccess {
            busy=true;scope.launch { try { notify(vm.testConnection());error="" } catch(e:Exception) { error="设置已保存，但连接失败：${e.message}" } finally { busy=false } }
        }.onFailure { error=it.message.orEmpty() }},modifier=Modifier.fillMaxWidth()) { Text(if(busy) "正在测试…" else "保存并测试连接") }
    }
}
@Composable fun SyncSettings(vm:AppViewModel,dismiss:()->Unit,notify:(String)->Unit) {
    var key by remember { mutableStateOf("") };var error by remember { mutableStateOf("") };var disable by remember { mutableStateOf(false) }
    val status by vm.status.collectAsState();val busy by vm.syncing.collectAsState()
    FullForm("私有同步",dismiss) {
        Text("在安卓、iOS 和网页中使用相同的同步密钥，就能共享餐食、身体测量、训练和每日目标。",style=MaterialTheme.typography.bodyLarge)
        Panel { Text(status); Text("常用餐食、动作库和对话只保存在本机。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
        OutlinedTextField(key,{key=it},Modifier.fillMaxWidth(),label={Text("同步密钥")},visualTransformation=PasswordVisualTransformation(),singleLine=true)
        Button(enabled=key.isNotBlank() && !busy,onClick={runCatching { vm.saveSyncKey(key);key="";notify("密钥已保存") }.onFailure { error=it.message.orEmpty() }},modifier=Modifier.fillMaxWidth()) { Text("保存密钥并同步") }
        OutlinedButton(enabled=!busy,onClick={vm.sync()},modifier=Modifier.fillMaxWidth()) { Text(if(busy) "正在同步…" else "立即同步") }
        Text("启用后，App 在前台每 15 秒同步一次。离线记录和照片会保留，联网后继续上传。",style=MaterialTheme.typography.bodyMedium)
        TextButton(onClick={disable=true}) { Text("关闭同步") }
    }
    if(disable) AlertDialog(onDismissRequest={disable=false},title={Text("关闭同步？")},text={Text("本机记录会保留。需要恢复同步时，重新填写原密钥。")},confirmButton={TextButton(onClick={vm.saveSyncKey("");disable=false}) { Text("关闭同步") }},dismissButton={TextButton(onClick={disable=false}) { Text("取消") }})
}
@Composable fun Library(vm:AppViewModel,type:RecordType,dismiss:()->Unit,notify:(String)->Unit) {
    val s by vm.snapshot.collectAsState(); var editor by remember { mutableStateOf<Record?>(null) };var selected by remember { mutableStateOf<Record?>(null) }
    FullForm(if(type==RecordType.FAVORITE) "常用餐食" else "我的动作库",dismiss,{IconButton(onClick={editor=Record.create(type)}) { Icon(Icons.Default.Add,"添加") }}) {
        val records=s.records.filter { it.type==type }
        if(records.isEmpty()) Empty("还没有保存内容","点击右上角添加，之后记录更方便")
        records.forEach { r -> Panel { RecordRow(r,{selected=r}) } }
    }
    selected?.let { r -> RecordDetail(vm,r,{selected=null},{selected=null;editor=r.copy()},notify) }
    editor?.let { r -> RecordEditor(vm,r,{editor=null},notify) }
}
@Composable fun Reminders(vm:AppViewModel,dismiss:()->Unit,notify:(String)->Unit) {
    val context=LocalContext.current; val store=vm.app.store
    var enabled by remember { mutableStateOf(store.get("reminder.enabled")=="yes") }; var time by remember { mutableStateOf(store.get("reminder.time","20:30")) }
    var meal by remember { mutableStateOf(store.get("reminder.meal","yes")=="yes") }; var body by remember { mutableStateOf(store.get("reminder.body","yes")=="yes") };var workout by remember { mutableStateOf(store.get("reminder.workout","no")=="yes") }
    var days by remember { mutableStateOf(store.get("reminder.days","1,3,5").split(',').mapNotNull { it.toIntOrNull() }) }
    val save:()->Unit={ listOf("enabled" to enabled,"meal" to meal,"body" to body,"workout" to workout).forEach { (key,value) -> store.set("reminder.$key",if(value) "yes" else "no") };store.set("reminder.time",time);store.set("reminder.days",days.joinToString(","));ReminderWorker.schedule(context) }
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> enabled=granted;save();if(!granted) notify("通知权限未开启，可在系统设置中允许通知") }
    FullForm("漏记提醒",dismiss,{TextButton(onClick={save();dismiss();notify("提醒已保存")}) { Text("保存") }}) {
        Toggle("启用漏记提醒","每天最多一条汇总通知",enabled,{ value -> if(value && Build.VERSION.SDK_INT>=33) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else {enabled=value;save()} })
        SettingsRow("每日时间",time) { val current=LocalTime.parse(time);TimePickerDialog(context,{_,h,m -> time="%02d:%02d".format(h,m)},current.hour,current.minute,true).show() }
        Toggle("餐食记录",checked=meal,onChange={meal=it});Toggle("身体测量",checked=body,onChange={body=it});Toggle("训练记录",checked=workout,onChange={workout=it})
        if(workout) { Text("训练星期");FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) { (1..7).forEach { day -> FilterChip(day in days,{days=if(day in days) days-day else days+day},label={Text(listOf("一","二","三","四","五","六","日")[day-1])}) } } }
        Text("当天已有该类真实记录就不再提醒，示例数据不算。安卓系统省电策略可能延迟通知；其他设备上的记录需先同步到本机。",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
