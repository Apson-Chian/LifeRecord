@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package ltd.apsonchian.liferecord.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.result.PickVisualMediaRequest
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.activity.compose.BackHandler
import ltd.apsonchian.liferecord.R
import androidx.compose.foundation.lazy.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.Send

import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*

@Composable fun Coach(vm:AppViewModel,notify:(String)->Unit,draft:String="",consumeDraft:()->Unit={}) {
    val snapshot by vm.snapshot.collectAsState()
    val chats by vm.conversations.collectAsState(); val selected by vm.selectedConversation.collectAsState(); val busy by vm.aiBusy.collectAsState(); val proposal by vm.proposal.collectAsState()
    var text by rememberSaveable { mutableStateOf("") }; val images by vm.draftPhotos.collectAsState(); var favorites by remember { mutableStateOf(false) }; var deleteId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(draft) { if(draft.isNotBlank()) { text=draft; consumeDraft() } }
    val scope=rememberCoroutineScope(); val list=rememberLazyListState()
    val keyboard=LocalSoftwareKeyboardController.current
    val drawer=rememberDrawerState(DrawerValue.Closed)
    BackHandler(drawer.isOpen) { scope.launch { drawer.close() } }
    val chat=chats.firstOrNull { it.getString("id")==selected }; val messages=chat?.getJSONArray("messages")?.objects().orEmpty()
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(12)) { uris -> scope.launch { runCatching { vm.readPhotos(uris) }.onSuccess { vm.draftPhotos.value=it }.onFailure { notify(it.message.orEmpty()) } } }
    LaunchedEffect(messages.size,selected) { if(messages.isNotEmpty()) list.animateScrollToItem(messages.size) }
    ModalNavigationDrawer(drawerState=drawer, drawerContent={
        ModalDrawerSheet(modifier=Modifier.widthIn(max=306.dp).fillMaxHeight(),drawerContainerColor=MaterialTheme.colorScheme.surface) {
            Row(Modifier.fillMaxWidth().padding(horizontal=16.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
                Text("对话",style=MaterialTheme.typography.titleLarge,modifier=Modifier.weight(1f))
                IconButton(onClick={vm.newConversation();scope.launch { drawer.close() }}) { Icon(Icons.Default.Add,"新建对话") }
                IconButton(onClick={scope.launch { drawer.close() }}) { Icon(Icons.Default.Close,"关闭对话列表") }
            }
            HorizontalDivider()
            if(chats.isEmpty()) Empty("还没有对话","新建一个对话，可以围绕训练、饮食或配料表连续追问。")
            LazyColumn(contentPadding=PaddingValues(12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                items(chats,key={it.getString("id")}) { c ->
                    val active=c.getString("id")==selected
                    Surface(shape=RoundedCornerShape(14.dp),color=if(active) MaterialTheme.colorScheme.primary.copy(alpha=.10f) else MaterialTheme.colorScheme.surfaceVariant.copy(alpha=.45f)) {
                        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                            TextButton(onClick={vm.selectedConversation.value=c.getString("id");scope.launch { drawer.close() }},modifier=Modifier.weight(1f)) {
                                Column(Modifier.fillMaxWidth()) {
                                    Text(c.getString("title"),maxLines=1,overflow=TextOverflow.Ellipsis,fontWeight=FontWeight.SemiBold)
                                    Text("${c.getJSONArray("messages").length()} 条消息",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                            if(active) Icon(Icons.Default.Check,null,tint=MaterialTheme.colorScheme.primary,modifier=Modifier.size(18.dp))
                            IconButton(onClick={deleteId=c.getString("id")},enabled=!busy) { Icon(Icons.Default.Delete,"删除对话") }
                        }
                    }
                }
            }
        }
    }) {
    Column(Modifier.fillMaxSize().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal=8.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically) {
            IconButton(onClick={keyboard?.hide();scope.launch { drawer.open() }}) { Icon(Icons.Default.Menu,"对话列表") }
            Column(Modifier.weight(1f)) { Text("你的 AI 教练",style=MaterialTheme.typography.titleLarge); Text(chat?.getString("title") ?: "聊聊饮食、训练和恢复",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis) }
            IconButton(onClick={favorites=true},modifier=Modifier.semantics { contentDescription="选择常用餐食" }) { Text("餐食",style=MaterialTheme.typography.labelMedium) }
            IconButton(onClick={vm.newConversation()}) { Icon(Icons.Default.Add,"新对话") }
        }
        LazyColumn(Modifier.weight(1f),state=list,contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            item { if(messages.isEmpty()) Panel { Text("从一个小问题开始",style=MaterialTheme.typography.titleLarge); Text("教练会参考你的本机记录。照片分析和营养草稿都可以在这里聊。",color=MaterialTheme.colorScheme.onSurfaceVariant)
                listOf("今天的蛋白质还差多少？","帮我复盘最近七天的训练","如何安排明天的饮食？").forEach { prompt -> OutlinedButton(onClick={text=prompt},Modifier.fillMaxWidth()) { Text(prompt) } }
            } }
            itemsIndexed(messages) { _, m -> ChatMessage(vm,m) }
            if(busy) item { Row(horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(20.dp),strokeWidth=2.dp); Text("正在思考，离开页面也会继续…",style=MaterialTheme.typography.bodySmall) } }
            proposal?.takeIf { it.conversation==selected }?.let { p -> item { Panel {
                Text("待复核的操作",style=MaterialTheme.typography.titleLarge)
                p.actions.forEach { a -> Text(actionDescription(a,p.original),style=MaterialTheme.typography.bodyMedium) }
                Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) { TextButton(onClick={vm.proposal.value=null}) { Text("放弃") }; Button(onClick={runCatching { vm.applyProposal() }.onFailure { notify(it.message.orEmpty()) }}) { Text("确认并保存 ${p.actions.size} 项") } }
            } } }
        }
        Surface(shape=androidx.compose.foundation.shape.RoundedCornerShape(24.dp),color=MaterialTheme.colorScheme.surface,border=BorderStroke(1.dp,MaterialTheme.colorScheme.primary.copy(alpha=.13f)),modifier=Modifier.padding(horizontal=12.dp,vertical=8.dp)) { Column(Modifier.padding(horizontal=8.dp,vertical=6.dp)) {
            if(images.isNotEmpty()) Row(verticalAlignment=Alignment.CenterVertically) { Text("已选 ${images.size} 张照片",modifier=Modifier.weight(1f)); TextButton(onClick={vm.draftPhotos.value=emptyList()}) { Text("清除") } }
            Row(verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.spacedBy(4.dp)) {
                IconButton(onClick={picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))},enabled=!busy) { Icon(Icons.Default.Add,"添加照片") }
                OutlinedTextField(text,{text=it},Modifier.weight(1f),placeholder={Text("和教练聊一聊…")},maxLines=5)
                IconButton(onClick={runCatching { vm.send(text,images);text="";vm.draftPhotos.value=emptyList() }.onFailure { notify(it.message.orEmpty()) }},enabled=!busy && (text.isNotBlank() || images.isNotEmpty())) { Icon(Icons.AutoMirrored.Filled.Send,"发送",tint=MaterialTheme.colorScheme.primary) }
            }
        } }
    }
    }
    if(favorites) FullForm("常用餐食",{favorites=false}) {
        val foods=snapshot.records.filter { it.type==RecordType.FAVORITE }
        if(foods.isEmpty()) Empty("还没有常用餐食","在设置中保存固定份量和营养，下次直接选择名称。")
        foods.forEach { food -> TextButton(onClick={text=food.title;favorites=false}) { Text("${food.title} · ${food.json.optString("portion","1 份")}") } }
    }
    deleteId?.let { id -> AlertDialog(onDismissRequest={deleteId=null},title={Text("删除此对话？")},text={Text("对话仅保存在本机，删除不会删除健康记录。")},confirmButton={TextButton(onClick={vm.deleteConversation(id);deleteId=null}) { Text("删除") }},dismissButton={TextButton(onClick={deleteId=null}) { Text("取消") }}) }
}
@Composable private fun ChatMessage(vm:AppViewModel,m:org.json.JSONObject) {
    val user=m.getString("role")=="user"
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val bubbleWidth=(maxWidth-(if(user) 52.dp else 94.dp)).coerceAtLeast(80.dp)
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.Bottom,horizontalArrangement=if(user) Arrangement.End else Arrangement.Start) {
            if(!user) {
                Image(painterResource(R.drawable.coach_avatar),null,Modifier.size(32.dp).clip(CircleShape),contentScale=ContentScale.Crop)
                Spacer(Modifier.width(10.dp))
            }
            Card(Modifier.widthIn(max=bubbleWidth),shape=RoundedCornerShape(20.dp),colors=CardDefaults.cardColors(containerColor=if(user) Purple else MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(horizontal=14.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    val files=m.optJSONArray("localPhotoFiles")?.strings().orEmpty()
                    if(files.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                        files.forEach { name ->
                            var bytes by remember(name) { mutableStateOf<ByteArray?>(null) }
                            LaunchedEffect(name) { bytes=withContext(Dispatchers.IO) { runCatching { vm.app.photos.chat(name) }.getOrNull() } }
                            bytes?.let { data ->
                                var full by remember { mutableStateOf(false) }
                                PhotoBytes(data,Modifier.size(72.dp).clickable { full=true })
                                if(full) PhotoViewer(vm,data) { full=false }
                            }
                        }
                    }
                    androidx.compose.foundation.text.selection.SelectionContainer {
                        if(user) Text(m.getString("content"),color=Color.White) else MarkdownText(m.getString("content"))
                    }
                }
            }
        }
    }
}
fun actionDescription(a:org.json.JSONObject,snapshot:Snapshot):String {
    val labels=mapOf("add_meal" to "新增餐食","update_meal" to "修改餐食","delete_meal" to "删除餐食","add_weight" to "新增身体测量","update_weight" to "修改身体测量","delete_weight" to "删除身体测量","add_workout" to "新增训练","update_workout" to "修改训练","delete_workout" to "删除训练","update_goals" to "修改目标","add_exercise_template" to "新增动作","update_exercise_template" to "修改动作","delete_exercise_template" to "删除动作")
    val fields=mapOf("name" to "名称","mealKind" to "餐次","calories" to "热量 kcal","protein" to "蛋白质 g","carbs" to "碳水 g","fat" to "脂肪 g","fiber" to "膳食纤维 g","weight" to "体重 kg","bodyFat" to "体脂率 %","waist" to "腰围 cm","note" to "备注","date" to "记录时间","endDate" to "结束时间","bodyParts" to "训练部位","bodyPart" to "默认部位","exercises" to "动作与组数","displayName" to "称呼","fitnessGoal" to "目标方向","height" to "身高 cm","baselineWeight" to "起始体重 kg","targetWeight" to "目标体重 kg","weeklyWeightTarget" to "每周变化 kg","calorieGoal" to "热量目标 kcal","proteinGoal" to "蛋白质目标 g","carbsGoal" to "碳水目标 g","fatGoal" to "脂肪目标 g","clearBodyFat" to "清空体脂率","clearWaist" to "清空腰围","clearBodyPart" to "清空默认部位")
    val original=snapshot.records.find { it.id.equals(a.optString("recordID"),true) }
    return buildString {
        append(labels[a.optString("type")] ?: "操作")
        original?.let { append(" · ${it.title} · ${it.date.localText()}") }
        a.keys().asSequence().filter { it in fields }.forEach { key ->
            val value=when(key) {
                "bodyParts" -> a.optJSONArray(key)?.strings()?.joinToString("、").orEmpty()
                "exercises" -> a.optJSONArray(key)?.objects()?.joinToString("；") { "${it.optString("name")}（${it.optJSONArray("sets")?.length() ?: 0} 组）" }.orEmpty()
                "date","endDate" -> runCatching { java.time.OffsetDateTime.parse(a.getString(key)).toLocalDateTime().toString().replace('T',' ') }.getOrDefault(a.opt(key)?.toString().orEmpty())
                "clearBodyFat","clearWaist","clearBodyPart" -> if(a.optBoolean(key)) "是" else "否"
                else -> a.opt(key)?.toString().orEmpty()
            }
            append("\n${fields[key]}：$value")
        }
    }
}
