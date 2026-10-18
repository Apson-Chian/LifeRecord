@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package ltd.apsonchian.liferecord.ui

import android.Manifest
import android.app.TimePickerDialog
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.sp
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import ltd.apsonchian.liferecord.service.*
import org.json.*
import java.time.LocalTime
import android.content.Intent
import android.net.Uri

@Composable fun Settings(vm:AppViewModel,s:Snapshot,notify:(String)->Unit) {
    var page by rememberSaveable { mutableStateOf("") }; var clear by remember { mutableStateOf(false) }; var reset by remember { mutableStateOf(false) }
    val status by vm.status.collectAsState(); val context=LocalContext.current; val scope=rememberCoroutineScope()
    val export=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri -> if(uri!=null) scope.launch {
        runCatching { val text=vm.export(); withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) } ?: error("无法写入文件") } }.onSuccess { notify("记录已导出") }.onFailure { notify(it.message.orEmpty()) }
    } }
    val ai by vm.config.collectAsState()
    if(page.isEmpty()) LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp,8.dp,16.dp,glassPageBottomPadding()),verticalArrangement=Arrangement.spacedBy(24.dp)) {
        item {PageTitle("设置","偏好与个人目标")}
        item {SettingsGroup("日常使用") {
            DestinationRow("个人与目标","${s.profile.optString("fitnessGoal")} · 身体与营养",Glyph.Person,MaterialTheme.colorScheme.primary) {page="profile"}
            GroupDivider()
            DestinationRow("记录与提醒","",Glyph.Workout,Color(0xFF31B8C4)) {page="recording"}
            GroupDivider()
            DestinationRow("教练与 AI",ai.optString("provider"),Glyph.Coach,MaterialTheme.colorScheme.primary) {page="coach"}
        }}
        item {SettingsGroup("应用与数据") {
            DestinationRow("外观与个性化","",Glyph.Person,Protein) {page="appearance"}
            GroupDivider()
            DestinationRow("跨设备同步",status,Glyph.Sync,Color(0xFF29AD5E)) {page="sync"}
            GroupDivider()
            DestinationRow("隐私、数据与帮助","",Glyph.Shield,Protein) {page="privacy"}
        }}
    }
    when(page) {
        "profile" -> ProfileForm(vm,s.profile,{page=""},notify)
        "recording" -> SettingsForm("记录与提醒",{page=""}) {
            SettingsGroup("常用记录") {
                DestinationRow("常用餐食","",Glyph.Meal,Carbs) {page="favorites"}
                GroupDivider()
                DestinationRow("我的动作库","",Glyph.Workout,Color(0xFF31B8C4)) {page="exercises"}
                GroupDivider()
                DestinationRow("管理训练部位","",Glyph.Workout,Color(0xFF31B8C4)) {page="parts"}
            }
            SettingsGroup("提醒") { DestinationRow("漏记提醒","",Glyph.Bell,Carbs) {page="reminders"} }
        }
        "coach" -> CoachSettings(vm,{page=""},{page="ai"},notify)
        "privacy" -> SettingsForm("隐私、数据与帮助",{page=""}) {
            Text("LifeRecord · Android 1.4 测试版",style=MaterialTheme.typography.titleMedium)
            SettingsRow("导出记录 JSON","包含照片编号；照片字节、对话和密钥不导出") {export.launch("LifeRecord-${java.time.LocalDate.now()}.json")}
            SettingsRow("重看引导","了解记录、AI 与私有同步") {page="";vm.onboarding.value=true}
            SettingsRow("清除本机数据","清除记录、对话、照片与密钥；云端记录保留") {reset=true}
            SettingsRow("清除示例数据","仅清除带有示例标记的记录") {clear=true}
            Text("记录保存在本机，密钥由 Android Keystore 加密。使用 AI 时，记录上下文会发送至你选择的接口；启用同步后才会上传至私有服务器。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        "appearance" -> SettingsForm("外观与个性化",{page=""}) {
            val mode by vm.appearance.collectAsState(); val color by vm.accent.collectAsState()
            Text("主题模式")
            FlowRow { listOf("system" to "跟随系统", "light" to "浅色", "dark" to "深色").forEach { (value,title) -> FilterChip(mode==value,{vm.personalize(value,color)},label={Text(title)}) } }
            Text("强调色")
            FlowRow { listOf("purple" to "紫色", "blue" to "蓝色", "green" to "绿色", "orange" to "橙色").forEach { (value,title) -> FilterChip(color==value,{vm.personalize(mode,value)},label={Text(title)}) } }
        }
        "ai" -> AISettings(vm,{page="coach"},notify)
        "sync" -> SyncSettings(vm,{page=""},notify)
        "favorites" -> Library(vm,RecordType.FAVORITE,{page="recording"},notify)
        "exercises" -> Library(vm,RecordType.EXERCISE,{page="recording"},notify)
        "parts" -> WorkoutPartManager(vm,{page="recording"},notify)
        "reminders" -> Reminders(vm,{page="recording"},notify)
    }
    if(reset) DeleteConfirmationDialog(
        title = "清除全部本机数据？",
        message = "请先导出需要保留的记录。这会清除记录、对话、照片、接口偏好和密钥，云端记录保留。",
        onDismiss = { reset = false },
        onConfirm = { runCatching { vm.resetLocalData(); reset = false; notify("本机数据已清除") }.onFailure { notify(it.message.orEmpty()) } },
        confirmLabel = "清除"
    )
    if(clear) DeleteConfirmationDialog(
        title = "清除示例数据？",
        message = "你自己记录和同步的内容会保留。",
        onDismiss = { clear = false },
        onConfirm = { vm.clearDemo(); clear = false; notify("示例数据已清除") },
        confirmLabel = "清除"
    )
}
@Composable private fun SettingsGroup(title:String,content:@Composable ColumnScope.()->Unit) {
    Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Text(title,Modifier.padding(start=16.dp),style=MaterialTheme.typography.bodyMedium.copy(fontWeight=FontWeight.Medium),color=MaterialTheme.colorScheme.onSurfaceVariant)
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(MaterialTheme.colorScheme.surface),content=content)
    }
}
@Composable private fun DestinationRow(title:String,subtitle:String,kind:Glyph,tint:Color,onClick:()->Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick=onClick).padding(horizontal=16.dp,vertical=16.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(13.dp)) {
        IconBadge(kind,tint)
        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)) {Text(title,style=MaterialTheme.typography.bodyLarge.copy(fontWeight=FontWeight.Medium));if(subtitle.isNotBlank()) Text(subtitle,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        AppIcon(Glyph.Chevron,MaterialTheme.colorScheme.onSurface.copy(alpha=.3f),Modifier.size(15.dp))
    }
}
@Composable private fun GroupDivider() {HorizontalDivider(Modifier.padding(start=73.dp,end=16.dp),color=MaterialTheme.colorScheme.onSurface.copy(alpha=.08f),thickness=.5.dp)}
@Composable fun SettingsRow(title:String,subtitle:String,onClick:()->Unit) { Row(Modifier.fillMaxWidth().clickable(onClick=onClick).padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(title,style=MaterialTheme.typography.titleMedium); Spacer(Modifier.height(4.dp)); Text(subtitle,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }; Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight,title) } }
@Composable fun Toggle(title:String,subtitle:String="",checked:Boolean,onChange:(Boolean)->Unit) { Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(title); if(subtitle.isNotBlank()) Text(subtitle,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }; Switch(checked,onChange) } }
@Composable fun ProfileForm(vm:AppViewModel,original:JSONObject,dismiss:()->Unit,notify:(String)->Unit) {
    val fields=remember { mutableStateMapOf<String,String>().apply { original.keys().forEach { put(it,original.opt(it)?.toString().orEmpty()) } } }
    var error by remember { mutableStateOf("") }
    SettingsForm("个人与目标",dismiss,{TextButton(onClick={runCatching {
        val p=original.copy(); fields.forEach { (key,value) -> if(key in listOf("displayName","fitnessGoal","id")) p.put(key,value) else if(key!="updatedAt") p.put(key,value.toDouble()) }; vm.saveProfile(p); dismiss(); notify("目标已保存")
    }.onFailure { error=it.message.orEmpty() }}) { Text("保存") }}) {
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
        SettingsGroup("个人资料") {
            Row(Modifier.fillMaxWidth().padding(16.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                Text("称呼",style=MaterialTheme.typography.bodyLarge)
                BasicTextField(fields["displayName"].orEmpty(),{fields["displayName"]=it},Modifier.weight(1f).semantics {contentDescription="称呼"},textStyle=MaterialTheme.typography.bodyLarge.copy(color=MaterialTheme.colorScheme.onSurface,textAlign=TextAlign.End),cursorBrush=SolidColor(MaterialTheme.colorScheme.primary),singleLine=true,
                    decorationBox={inner -> Box(contentAlignment=Alignment.CenterEnd) {if(fields["displayName"].isNullOrEmpty()) Text("可选",style=MaterialTheme.typography.bodyLarge,color=MaterialTheme.colorScheme.onSurfaceVariant);inner()}})
            }
            FieldDivider()
            Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
                Text("当前目标",style=MaterialTheme.typography.bodyLarge)
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceVariant).padding(2.dp).selectableGroup()) {
                    listOf("增肌","减脂","维持").forEach {goal -> Box(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(if(fields["fitnessGoal"]==goal) MaterialTheme.colorScheme.surface else Color.Transparent).selectable(fields["fitnessGoal"]==goal,role=Role.Tab,onClick={fields["fitnessGoal"]=goal}).padding(vertical=6.dp),contentAlignment=Alignment.Center) {Text(goal,style=MaterialTheme.typography.bodySmall)} }
                }
            }
        }
        val groups=listOf(
            "身体与体重" to listOf(Triple("height","身高","cm"),Triple("baselineWeight","起始体重","kg"),Triple("targetWeight","目标体重","kg"),Triple("weeklyWeightTarget","每周体重变化","kg")),
            "每日营养目标" to listOf(Triple("calorieGoal","热量","kcal"),Triple("proteinGoal","蛋白质","g"),Triple("carbsGoal","碳水","g"),Triple("fatGoal","脂肪","g"))
        )
        groups.forEach { (heading,entries) -> SettingsGroup(heading) {
            entries.forEachIndexed {index,(key,title,unit) ->
                if(index>0) FieldDivider()
                Row(Modifier.fillMaxWidth().heightIn(min=52.dp).padding(horizontal=16.dp,vertical=12.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    Text(title,Modifier.weight(1f),style=MaterialTheme.typography.bodyLarge)
                    BasicTextField(fields[key].orEmpty(),{fields[key]=it},Modifier.width(96.dp).semantics {contentDescription=title},textStyle=MaterialTheme.typography.bodyLarge.copy(color=MaterialTheme.colorScheme.primary,textAlign=TextAlign.End),cursorBrush=SolidColor(MaterialTheme.colorScheme.primary),singleLine=true,keyboardOptions=KeyboardOptions(keyboardType=if(key=="weeklyWeightTarget") KeyboardType.Text else KeyboardType.Decimal))
                    Text(unit,style=MaterialTheme.typography.bodyLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } }
        Text("每周体重变化：减重填负数。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)

    }
}
@Composable private fun CoachSettings(vm:AppViewModel,dismiss:()->Unit,openInterface:()->Unit,notify:(String)->Unit) {
    val current by vm.config.collectAsState()
    val identity by vm.coachIdentity.collectAsState()
    var showProfile by rememberSaveable {mutableStateOf(false)}
    var instructions by rememberSaveable { mutableStateOf(current.optString("instructions")) }
    val canWrite=current.optBoolean("canWrite")
    var error by remember { mutableStateOf("") }
    fun save():Boolean = runCatching {
        vm.saveConfig(vm.config.value.copy().put("instructions",instructions).put("canWrite",canWrite),null)
    }.fold({true},{error=it.message.orEmpty();false})
    SettingsForm("教练与 AI",dismiss,{TextButton(onClick={if(save()) {dismiss();notify("教练偏好已保存")}}) {Text("保存")}}) {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surface).clickable {showProfile=true}.padding(16.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            CoachAvatar(identity,36.dp);Text(identity.name,Modifier.weight(1f),style=MaterialTheme.typography.bodyLarge)
            Text("名称与头像",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant);AppIcon(Glyph.Chevron,MaterialTheme.colorScheme.onSurfaceVariant,Modifier.size(12.dp))
        }
        TextFieldRow("长期偏好，例如训练安排、忌口",instructions,{instructions=it},lines=3)
        Toggle("允许 AI 修改记录",if(canWrite) "按你的明确要求更改记录。" else "只读模式，仅分析和回答。",canWrite,{runCatching {vm.setCoachWrites(it)}.onFailure {error=it.message.orEmpty()}})
        SettingsGroup("AI 服务") {
            DestinationRow("接口与模型","${current.optString("provider")} · ${current.optString("model")}",Glyph.Coach,MaterialTheme.colorScheme.primary) { if(save()) openInterface() }
        }
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
    }
    if(showProfile) CoachProfile(vm,{showProfile=false},notify)
}

@Composable fun AISettings(vm:AppViewModel,dismiss:()->Unit,notify:(String)->Unit) {
    val current by vm.config.collectAsState()
    var provider by remember { mutableStateOf(current.getString("provider")) }
    val fields=remember { mutableStateMapOf<String,String>().apply { listOf("endpoint","model","auth","header","maxPhotos","temperature","maxTokens","instructions","tokenParameter","extraBody","imageDetail").forEach { put(it,current.opt(it)?.toString() ?: if(it=="tokenParameter") "max_tokens" else if(it=="extraBody") "{}" else "") } } }
    var vision by remember { mutableStateOf(current.optBoolean("vision")) }; var canWrite by remember { mutableStateOf(current.optBoolean("canWrite")) }
    var sendTemperature by remember { mutableStateOf(current.optBoolean("sendTemperature",true)) }; var jsonMode by remember { mutableStateOf(current.optBoolean("jsonMode",true)) }
    var key by remember { mutableStateOf("") }; var keyTouched by remember { mutableStateOf(false) }; var busy by remember { mutableStateOf(false) }; var error by remember { mutableStateOf("") }
    val savedProfiles by vm.apiProfiles.collectAsState()
    var profileName by remember { mutableStateOf("") }
    var selectedProfile by remember { mutableStateOf("") }
    fun loadProfile(c:JSONObject) {
        provider=c.optString("provider", "自定义")
        sendTemperature=c.optBoolean("sendTemperature",true);jsonMode=c.optBoolean("jsonMode",true)
        fields.keys.toList().forEach { fields[it]=c.opt(it)?.toString().orEmpty() }
        vision=c.optBoolean("vision");canWrite=c.optBoolean("canWrite");key="";keyTouched=false
    }
    val scope=rememberCoroutineScope()
    val context=LocalContext.current
    val officialDeepSeek=AIAuthentication.officialDeepSeek(fields["endpoint"].orEmpty())
    val save:()->Unit={
        val c=JSONObject().put("provider",provider).put("vision",vision).put("canWrite",canWrite).put("sendTemperature",sendTemperature).put("jsonMode",jsonMode)
        fields.forEach { (name,value) -> c.put(name,when(name) { "temperature" -> value.toDouble(); "maxPhotos","maxTokens" -> value.toInt(); else -> value }) }
        vm.saveConfig(c,if(keyTouched) key else null)
    }
    SettingsForm("接口与模型",dismiss,{TextButton(enabled=!busy,onClick={runCatching { save();dismiss();notify("AI 设置已保存") }.onFailure { error=it.message.orEmpty() }}) { Text("保存") }}) {
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
        FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) { providers.forEach { p -> FilterChip(provider==p,onClick={
            if(provider!=p) { provider=p; val c=org.json.JSONObject(vm.app.store.get("ai.profile.$p",providerConfig(p).toString())); sendTemperature=c.optBoolean("sendTemperature",true);jsonMode=c.optBoolean("jsonMode",true); fields.keys.toList().forEach { fields[it]=c.opt(it)?.toString().orEmpty() }; vision=c.optBoolean("vision"); key="";keyTouched=false }
        },label={Text(p)}) } }
        SettingsDisclosure("保存与切换接口") {
        Text("已保存的接口",style=MaterialTheme.typography.titleSmall)
        FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) { savedProfiles.forEach { p ->
            FilterChip(selectedProfile==p.getString("id"), onClick={selectedProfile=p.getString("id");profileName=p.getString("name");loadProfile(p.getJSONObject("config"))}, label={Text(p.getString("name"))})
        } }
        TextFieldRow("配置名称",profileName,{profileName=it})
        FlowRow {
            TextButton(onClick={runCatching { save();selectedProfile=vm.saveAPIProfile(profileName);notify("接口配置已保存") }.onFailure { error=it.message.orEmpty() }}) {Text("另存为新配置")}
            if(selectedProfile.isNotEmpty()) {
                TextButton(onClick={runCatching { save();vm.saveAPIProfile(profileName,selectedProfile);notify("接口配置已更新") }.onFailure { error=it.message.orEmpty() }}) {Text("更新所选配置")}
                TextButton(onClick={vm.deleteAPIProfile(selectedProfile);selectedProfile="";profileName=""}) {Text("删除所选配置")}
            }
        }
        }
        TextFieldRow("接口地址（HTTPS）",fields["endpoint"].orEmpty(),{fields["endpoint"]=it});TextFieldRow("模型名",fields["model"].orEmpty(),{fields["model"]=it})
        if(officialDeepSeek) {
            Text("DeepSeek 官方接口使用 Authorization: Bearer；更新会自动纠正旧认证配置。请使用开放平台创建的完整 API Key。deepseek-flash 支持图片；已有配置可开启下方的“支持图片”。",style=MaterialTheme.typography.bodySmall)
            TextButton(onClick={context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://platform.deepseek.com/api_keys")))}) { Text("打开 DeepSeek API Key 页面") }
        } else FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) { listOf("Bearer","api-key","自定义").forEach { auth -> FilterChip(fields["auth"]==auth,{fields["auth"]=auth},label={Text(auth)}) } }
        if(!officialDeepSeek && fields["auth"]=="自定义") TextFieldRow("认证请求头",fields["header"].orEmpty(),{fields["header"]=it})
        SecretFieldRow("API Key（留空保留已有密钥）",key,{key=it;keyTouched=true})
        Text("每个服务商的密钥分别保存。切换不会把其他服务商的密钥发到当前接口。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        Toggle("支持图片","需要模型本身支持视觉输入",vision,{vision=it})
        SettingsDisclosure("高级参数") {
        listOf("maxPhotos" to "最多照片数（1–12）","temperature" to "Temperature（0–2）","maxTokens" to "最大输出 Token（256–65536）").forEach { (name,label) -> TextFieldRow(label,fields[name].orEmpty(),{fields[name]=it},true) }
        Text("输出 Token 参数")
        FlowRow { listOf("max_tokens","max_completion_tokens").forEach { name -> FilterChip(fields["tokenParameter"]==name,{fields["tokenParameter"]=name},label={Text(name)}) } }
        Toggle("发送 Temperature","部分推理模型不接受此参数",sendTemperature,{sendTemperature=it})
        Toggle("发送 JSON 格式参数","不兼容时关闭；仍通过提示词请求结构化回复",jsonMode,{jsonMode=it})
        TextFieldRow("图片 detail 参数（留空不发送）",fields["imageDetail"].orEmpty(),{fields["imageDetail"]=it})
        TextFieldRow("额外请求参数 JSON",fields["extraBody"].orEmpty(),{fields["extraBody"]=it},lines=4)
        Text("只支持 OpenAI Chat Completions 兼容接口；改接口地址后需为新地址重新保存密钥。扩展参数用于 top_p 等，不要填写密钥。",style=MaterialTheme.typography.bodySmall)
        }
        AppButton(enabled=!busy,onClick={runCatching { save() }.onSuccess {
            busy=true;scope.launch { try { notify(vm.testConnection());error="" } catch(e:Exception) { error="设置已保存，但连接失败：${e.message}" } finally { busy=false } }
        }.onFailure { error=it.message.orEmpty() }},modifier=Modifier.fillMaxWidth()) { Text(if(busy) "正在测试…" else "保存并测试连接") }
    }
}
@Composable fun SyncSettings(vm:AppViewModel,dismiss:()->Unit,notify:(String)->Unit) {
    var base by remember { mutableStateOf(vm.app.store.get("sync.base",Network.BASE)) }; var key by remember { mutableStateOf("") };var error by remember { mutableStateOf("") };var disable by remember { mutableStateOf(false) }
    val status by vm.status.collectAsState();val busy by vm.syncing.collectAsState()
    SettingsForm("私有同步",dismiss) {
        Text("在安卓、iOS 和网页中使用你自己的独立同步密钥，就能共享餐食、身体测量、训练和每日目标。",style=MaterialTheme.typography.bodyLarge)
        Panel { Text(status); Text("每位测试者使用独立密钥，不能分享你的私人密钥。常用餐食、动作库和对话只保存在本机。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
        TextFieldRow("同步服务器（HTTPS）",base,{base=it})
        SecretFieldRow("独立用户同步密钥",key,{key=it})
        AppButton(enabled=key.isNotBlank() && !busy,onClick={runCatching { vm.saveSyncKey(key,base);key="";notify("密钥已保存") }.onFailure { error=it.message.orEmpty() }},modifier=Modifier.fillMaxWidth()) { Text("保存密钥并同步") }
        SoftButton(enabled=!busy,onClick={vm.sync()},modifier=Modifier.fillMaxWidth()) { Text(if(busy) "正在同步…" else "立即同步") }
        Text("启用后，App 在前台每 15 秒同步一次。离线记录和照片会保留，联网后继续上传。",style=MaterialTheme.typography.bodyMedium)
        TextButton(onClick={disable=true}) { Text("关闭同步") }
    }
    if(disable) AlertDialog(onDismissRequest={disable=false},title={Text("关闭同步？")},text={Text("本机记录会保留。需要恢复同步时，重新填写原密钥。")},confirmButton={TextButton(onClick={vm.saveSyncKey("");disable=false}) { Text("关闭同步") }},dismissButton={TextButton(onClick={disable=false}) { Text("取消") }})
}
@Composable fun Library(vm:AppViewModel,type:RecordType,dismiss:()->Unit,notify:(String)->Unit) {
    val s by vm.snapshot.collectAsState(); var editor by remember { mutableStateOf<Record?>(null) };var selected by remember { mutableStateOf<Record?>(null) }
    SettingsForm(if(type==RecordType.FAVORITE) "常用餐食" else "我的动作库",dismiss,{IconButton(onClick={editor=Record.create(type)}) { Icon(Icons.Default.Add,"添加") }}) {
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
    SettingsForm("漏记提醒",dismiss,{TextButton(onClick={save();dismiss();notify("提醒已保存")}) { Text("保存") }}) {
        Toggle("启用漏记提醒","每天最多一条汇总通知",enabled,{ value -> if(value && Build.VERSION.SDK_INT>=33) permission.launch(Manifest.permission.POST_NOTIFICATIONS) else {enabled=value;save()} })
        SettingsRow("每日时间",time) { val current=LocalTime.parse(time);TimePickerDialog(context,{_,h,m -> time="%02d:%02d".format(h,m)},current.hour,current.minute,true).show() }
        Toggle("餐食记录",checked=meal,onChange={meal=it});Toggle("身体测量",checked=body,onChange={body=it});Toggle("训练记录",checked=workout,onChange={workout=it})
        if(workout) { Text("训练星期");FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) { (1..7).forEach { day -> FilterChip(day in days,{days=if(day in days) days-day else days+day},label={Text(listOf("一","二","三","四","五","六","日")[day-1])}) } } }
        Text("当天已有该类真实记录就不再提醒，示例数据不算。安卓系统省电策略可能延迟通知；其他设备上的记录需先同步到本机。",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Settings use the same in-tab push hierarchy as iOS. Editors elsewhere remain sheets. */
@Composable private fun SettingsForm(title:String,dismiss:()->Unit,actions:@Composable RowScope.()->Unit={},content:@Composable ColumnScope.()->Unit) {
    SubPage(title,dismiss,actions,content)
}

@Composable private fun FieldDivider() {HorizontalDivider(Modifier.padding(horizontal=16.dp),color=MaterialTheme.colorScheme.onSurface.copy(alpha=.08f),thickness=.5.dp)}

@Composable private fun SettingsDisclosure(title:String,content:@Composable ColumnScope.()->Unit) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        TextButton(onClick={expanded=!expanded},contentPadding=PaddingValues(0.dp)) { Text(if(expanded) "收起$title" else title) }
        if(expanded) content()
    }
}
