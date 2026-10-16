@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package ltd.apsonchian.liferecord.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.result.PickVisualMediaRequest
import androidx.compose.foundation.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.sp
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
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
    val chats by vm.conversations.collectAsState(); val selected by vm.selectedConversation.collectAsState(); val tasks by vm.activeCoachTasks.collectAsState(); val proposal by vm.proposal.collectAsState()
    val busy=selected in tasks
    val identity by vm.coachIdentity.collectAsState()
    var showProfile by rememberSaveable {mutableStateOf(false)}
    var text by rememberSaveable { mutableStateOf("") }; val images by vm.draftPhotos.collectAsState(); var favorites by remember { mutableStateOf(false) }; var deleteId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(draft) { if(draft.isNotBlank()) { text=draft; consumeDraft() } }
    val scope=rememberCoroutineScope(); val list=rememberLazyListState()
    val keyboard=LocalSoftwareKeyboardController.current
    val inputFocus=remember {FocusRequester()}
    val config by vm.config.collectAsState()
    val drawer=rememberDrawerState(DrawerValue.Closed)
    BackHandler(drawer.isOpen) { scope.launch { drawer.close() } }
    val chat=chats.firstOrNull { it.getString("id")==selected }; val messages=chat?.getJSONArray("messages")?.objects().orEmpty()
    val hasProposal=proposal?.conversation==selected
    val bottomIndex=1+messages.size+(if(busy) 1 else 0)+(if(hasProposal) 1 else 0)
    LaunchedEffect(selected,messages.size,busy,proposal) {
        if(messages.isEmpty() && !busy && !hasProposal) return@LaunchedEffect
        withFrameNanos { }
        list.scrollToItem(bottomIndex)
    }
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
        Box(Modifier.fillMaxWidth().height(60.dp).padding(horizontal=16.dp),contentAlignment=Alignment.Center) {
            Row(Modifier.padding(horizontal=96.dp).clip(RoundedCornerShape(12.dp)).clickable {showProfile=true}.padding(4.dp).testTag("coach-title").semantics(mergeDescendants=true) {contentDescription="自定义教练：${identity.name}"},verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(7.dp)) {
                CoachAvatar(identity,28.dp)
                Column(Modifier.weight(1f,false)) {
                    Text(identity.name,style=MaterialTheme.typography.titleMedium,maxLines=1,overflow=TextOverflow.Ellipsis)
                    chat?.let {Text(it.getString("title"),style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)}
                }
                AppIcon(Glyph.Chevron,MaterialTheme.colorScheme.onSurfaceVariant,Modifier.size(10.dp).then(Modifier.rotate(90f)))
            }
            SymbolButton(Glyph.Sidebar,"对话列表",{keyboard?.hide();scope.launch {drawer.open()}},Modifier.align(Alignment.CenterStart))
            Row(Modifier.align(Alignment.CenterEnd).clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.surface.copy(alpha=.85f))) {
                IconButton(onClick={favorites=true}) {AppIcon(Glyph.Meal,MaterialTheme.colorScheme.primary,Modifier.size(21.dp),"选择常用餐食")}
                IconButton(onClick=vm::newConversation) {AppIcon(Glyph.Compose,MaterialTheme.colorScheme.primary,Modifier.size(21.dp),"新对话")}
            }
        }
        LazyColumn(Modifier.weight(1f).testTag("coach-messages"),state=list,contentPadding=PaddingValues(horizontal=20.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
            item { if(messages.isEmpty()) Column(verticalArrangement=Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    CoachAvatar(identity,40.dp)
                    Text(identity.name,fontSize=22.sp,fontWeight=FontWeight.Bold)
                }
                Text(if(config.optBoolean("vision")) "可以发送食物、配料表、营养表或训练截图，也可以让我替你记录数据。" else "当前模型未开启图片输入，请在设置中切换多模态模型。",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
                val prompts=listOf("分析最近的身体趋势","分析今天是否适合加餐","看看这张配料表")
                prompts.chunked(2).forEach { row -> Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    row.forEach { prompt ->
                        Box(Modifier.weight(1f).clip(RoundedCornerShape(15.dp)).background(MaterialTheme.colorScheme.surface.copy(alpha=.6f)).clickable {text=prompt;inputFocus.requestFocus();keyboard?.show()}.defaultMinSize(minHeight=52.dp).padding(horizontal=11.dp,vertical=8.dp),contentAlignment=Alignment.CenterStart) {
                            Text(prompt,style=MaterialTheme.typography.bodySmall.copy(fontWeight=FontWeight.Medium))
                        }
                    }
                    if(row.size==1) Spacer(Modifier.weight(1f))
                }}
            } }
            itemsIndexed(messages) { _, m -> ChatMessage(vm,m) }
            if(busy) item { Panel {Row(horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(20.dp),strokeWidth=2.dp); Text("正在生成，离开页面也会继续…",Modifier.weight(1f),style=MaterialTheme.typography.bodySmall);TextButton(onClick={vm.stopCoach(selected)}) {Text("停止")} }} }
            proposal?.takeIf { it.conversation==selected }?.let { p -> item { Panel {
                Text("待复核的操作",style=MaterialTheme.typography.titleLarge)
                p.actions.forEach { a -> Text(actionDescription(a,p.original),style=MaterialTheme.typography.bodyMedium) }
                Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) { TextButton(onClick={vm.proposal.value=null}) { Text("放弃") }; AppButton(onClick={runCatching { vm.applyProposal() }.onFailure { notify(it.message.orEmpty()) }}) { Text("确认并保存 ${p.actions.size} 项") } }
            } } }
            item(key="conversation-bottom") { Spacer(Modifier.height(1.dp).testTag("coach-bottom")) }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal=24.dp),verticalAlignment=Alignment.CenterVertically) {
            Text("允许 AI 修改记录",Modifier.weight(1f),style=MaterialTheme.typography.bodySmall)
            Switch(config.optBoolean("canWrite"),{runCatching {vm.setCoachWrites(it)}.onFailure {notify(it.message.orEmpty())}},enabled=tasks.isEmpty(),modifier=Modifier.testTag("coach-write-toggle"))
        }
        Surface(shape=RoundedCornerShape(25.dp),color=MaterialTheme.colorScheme.surface.copy(alpha=.8f),border=BorderStroke(.7.dp,Color.White.copy(alpha=.2f)),modifier=Modifier.padding(horizontal=16.dp,vertical=8.dp)) {
            Column(Modifier.padding(7.dp),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                if(images.isNotEmpty()) {
                    Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        images.forEachIndexed { index,bytes -> Box {
                            PhotoBytes(bytes,Modifier.size(64.dp))
                            IconButton(onClick={vm.draftPhotos.value=images.filterIndexed { i,_ -> i!=index }},modifier=Modifier.align(Alignment.TopEnd).size(26.dp).background(Color.Black.copy(alpha=.5f),CircleShape)) {Icon(Icons.Default.Close,"移除照片 ${index+1}",tint=Color.White,modifier=Modifier.size(15.dp))}
                        } }
                    }
                    Text("已选 ${images.size} 张照片",Modifier.padding(horizontal=7.dp),style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
                val send={runCatching {vm.send(text,images);text="";vm.draftPhotos.value=emptyList()}.onFailure {notify(it.message.orEmpty())};Unit}
                val sendEnabled=!busy && (text.isNotBlank() || images.isNotEmpty())
                Row(verticalAlignment=Alignment.Bottom,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    PhotoInput(vm,images,config.optInt("maxPhotos",6),!busy && config.optBoolean("vision"),{vm.draftPhotos.value=it},notify) {open ->
                        Box(Modifier.size(44.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha=.6f)).clickable(enabled=!busy && config.optBoolean("vision"),onClick=open),contentAlignment=Alignment.Center) {
                            AppIcon(Glyph.Plus,MaterialTheme.colorScheme.onSurface,Modifier.size(21.dp),"添加照片")
                        }
                    }
                    BasicTextField(text,{text=it},Modifier.weight(1f).focusRequester(inputFocus).defaultMinSize(minHeight=44.dp).padding(vertical=10.dp),textStyle=MaterialTheme.typography.bodyLarge.copy(color=MaterialTheme.colorScheme.onSurface),cursorBrush=SolidColor(MaterialTheme.colorScheme.primary),maxLines=5,
                        keyboardOptions=KeyboardOptions(imeAction=ImeAction.Send),keyboardActions=KeyboardActions(onSend={if(sendEnabled) send()}),decorationBox={inner ->
                            Box {if(text.isEmpty()) Text("问问题，或让我替你记录…",style=MaterialTheme.typography.bodyLarge,color=MaterialTheme.colorScheme.onSurfaceVariant);inner()}
                        })
                    Box(Modifier.size(44.dp).clip(CircleShape).background(if(sendEnabled || busy) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha=.15f)).clickable(enabled=sendEnabled || busy,onClick={if(busy) vm.stopCoach(selected) else send()}),contentAlignment=Alignment.Center) {
                        if(busy) Icon(Icons.Default.Close,"停止生成",tint=Color.White,modifier=Modifier.size(24.dp)) else AppIcon(Glyph.Up,Color.White,Modifier.size(24.dp),"发送")
                    }
                }
            }
        }

    }
    if(showProfile) CoachProfile(vm,{showProfile=false},notify)
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
    val identity by vm.coachIdentity.collectAsState()
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val bubbleWidth=(maxWidth-(if(user) 52.dp else 94.dp)).coerceAtLeast(80.dp)
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.Bottom,horizontalArrangement=if(user) Arrangement.End else Arrangement.Start) {
            if(!user) {
                CoachAvatar(identity)
                Spacer(Modifier.width(10.dp))
            }
            Surface(Modifier.widthIn(max=bubbleWidth),shape=RoundedCornerShape(20.dp),color=if(user) Purple else MaterialTheme.colorScheme.surface.copy(alpha=.32f),border=if(user) null else BorderStroke(.5.dp,Color.White.copy(alpha=.14f))) {
                Column(Modifier.padding(horizontal=14.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    if(!user) Text(identity.name,style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
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
                        if(user) Text(m.getString("content"),color=Color.White,style=MaterialTheme.typography.bodyLarge) else MarkdownText(m.getString("content"))
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
