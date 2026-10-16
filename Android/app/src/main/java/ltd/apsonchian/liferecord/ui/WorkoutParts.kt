@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class,androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
package ltd.apsonchian.liferecord.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import org.json.*
import kotlin.math.abs

private val PartTint=Color(0xFF31B8C4)
private fun names(parts:List<String>)=parts.joinToString("、").ifBlank {"未分类"}

@Composable fun WorkoutDetails(vm:AppViewModel,records:List<Record>,dismiss:()->Unit,edit:(Record)->Unit,notify:(String)->Unit) {
    var category by rememberSaveable {mutableStateOf("训练记录")}
    var manager by rememberSaveable {mutableStateOf(false)}
    var rename by rememberSaveable {mutableStateOf<String?>(null)}
    var library by rememberSaveable {mutableStateOf(false)}
    var assistant by rememberSaveable {mutableStateOf(false)}
    var focus by rememberSaveable {mutableStateOf<String?>(null)}
    var message by remember {mutableStateOf("")}
    val busy by vm.partsBusy.collectAsState();val scope=rememberCoroutineScope()
    val ids=records.map {it.id}.toSet()
    if(manager) {WorkoutPartManager(vm,{manager=false},notify,initialRename=rename);return}
    if(library) {Library(vm,RecordType.EXERCISE,{library=false},notify);return}
    SubPage("训练明细",dismiss) {
        Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {listOf("训练记录","按部位").forEach {FilterChip(category==it,{category=it},label={Text(it)})}}
        if(category=="训练记录") {
            if(records.isEmpty()) Empty("还没有训练记录","在今日页开始或补记训练")
            records.sortedByDescending {it.date}.forEach {r ->Panel(Modifier.clickable {edit(r)},tint=PartTint) {Text(r.date.localText(),style=MaterialTheme.typography.titleMedium);Text(WorkoutCalendar.content(r),style=MaterialTheme.typography.bodyMedium);Text(if(r.json.isNull("endDate")) "进行中" else "结束 ${r.json.getDouble("endDate").localText()}",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}}
        } else {
            AppButton(onClick={focus=null;assistant=true},modifier=Modifier.fillMaxWidth()) {Text("与 AI 对话调整训练部位")}
            SoftButton(onClick={rename=null;manager=true},modifier=Modifier.fillMaxWidth()) {Text("管理训练部位")}
            SoftButton(onClick={library=true},modifier=Modifier.fillMaxWidth()) {Text("管理和添加动作")}
            val unclassified=records.filter {WorkoutParts.of(it).isEmpty() && WorkoutParts.description(it).isNotBlank()}
            if(unclassified.isNotEmpty()) AppButton(onClick={scope.launch {
                message=""
                try {message="已归类 ${vm.classifyWorkoutParts(unclassified.map {it.id}.toSet())} 条；证据不足的记录仍可手动选择部位。"}
                catch(e:CancellationException) {throw e}
                catch(e:Exception) {message="AI 归类失败：${e.message.orEmpty()}"}
            }},enabled=!busy,modifier=Modifier.fillMaxWidth()) {Text(if(busy) "AI 正在归类…" else "AI 归类 ${unclassified.size} 条未分类训练")}
            if(message.isNotBlank()) Text(message,style=MaterialTheme.typography.bodySmall)
            val completed=records.filter {WorkoutCalendar.completed(it,now())}
            val groups=completed.flatMap(WorkoutParts::of).distinct().sorted()
            if(groups.isEmpty()) Empty("还没有训练部位记录","在训练详情直接选择训练部位，也可以让 AI 根据已有记录归类。")
            groups.forEach {part ->
                val entries=completed.filter {part in WorkoutParts.of(it)}.sortedByDescending {it.date}
                Panel(tint=PartTint) {
                    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {Text(part,style=MaterialTheme.typography.titleLarge);Text("${entries.size} 次",color=PartTint)}
                    PartTimeline(part,entries,edit)
                    Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick={focus=part;assistant=true}) {Text("AI 调整")}
                        TextButton(onClick={rename=part;manager=true}) {Text("部位改名")}
                    }
                }
            }
        }
    }
    if(assistant) WorkoutPartAssistant(vm,ids,focus,{assistant=false},notify)
}

@Composable private fun PartTimeline(part:String,records:List<Record>,edit:(Record)->Unit) {
    var selected by rememberSaveable(part) {mutableStateOf<String?>(null)}
    var all by rememberSaveable(part) {mutableStateOf(false)}
    val first=records.minOf {it.date};val last=records.maxOf {it.date};val padding=maxOf(86400.0,(last-first)*.05)
    val start=first-padding;val span=last+padding-start
    Canvas(Modifier.fillMaxWidth().height(72.dp).testTag("part-timeline-$part").pointerInput(records.map {it.id to it.updated}) {detectTapGestures {point->
        val date=start+point.x/size.width*span;selected=records.minByOrNull {abs(it.date-date)}?.id
    }}) {
        drawLine(PartTint.copy(alpha=.3f),Offset(0f,size.height/2),Offset(size.width,size.height/2),1.dp.toPx())
        records.forEach {r ->drawCircle(PartTint,if(selected==r.id) 6.dp.toPx() else 4.dp.toPx(),Offset(((r.date-start)/span*size.width).toFloat(),size.height/2))}
    }
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {Text(first.localText().take(10),style=MaterialTheme.typography.labelSmall);Text(last.localText().take(10),style=MaterialTheme.typography.labelSmall)}
    selected?.let {id->records.find {it.id==id}?.let {r -> TextButton(onClick={edit(r)}) {Text("${r.date.localText()} · 编辑此次训练")}}}
    TextButton(onClick={all=!all}) {Text(if(all) "收起训练记录" else "选择训练记录")}
    if(all) records.forEach {r -> TextButton(onClick={edit(r)}) {Text("${r.date.localText()} · ${WorkoutCalendar.title(r)}")}}
}

@Composable fun WorkoutPartManager(vm:AppViewModel,dismiss:()->Unit,notify:(String)->Unit,initialRename:String?=null,modal:Boolean=false,onRename:(String,String)->Unit={_,_->}) {
    val catalog by vm.bodyPartChoices.collectAsState();val snapshot by vm.snapshot.collectAsState()
    var name by rememberSaveable {mutableStateOf("")}
    var target by rememberSaveable {mutableStateOf(initialRename)}
    var edited by rememberSaveable {mutableStateOf(initialRename.orEmpty())}
    var error by remember {mutableStateOf("")}
    var repair by remember {mutableStateOf<PartPlan?>(null)}
    val content:@Composable ColumnScope.()->Unit={
        Text("新增训练部位",style=MaterialTheme.typography.titleLarge)
        TextFieldRow("例如：二头、三头、小臂",name,{name=it})
        AppButton(onClick={runCatching {vm.addBodyPart(name);name="";error=""}.onFailure {error=it.message.orEmpty()}},enabled=name.isNotBlank()) {Text("添加")}
        if("手臂" in catalog) SoftButton(onClick={vm.savePartChoices(WorkoutParts.splitArms(catalog))}) {Text("将手臂细分为二头、三头、小臂")}
        val plan=vm.armRepairPlan()
        if(plan.changes.isNotEmpty()) SoftButton(onClick={repair=plan}) {Text("修复 ${plan.changes.size} 条手臂归类")}
        Text("以后训练可选的部位",style=MaterialTheme.typography.titleLarge)
        Text("移除只影响以后选择，已有训练记录不会丢失。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        catalog.forEach {part ->Row(Modifier.fillMaxWidth().heightIn(min=48.dp),verticalAlignment=Alignment.CenterVertically) {
            Text(part,Modifier.weight(1f));TextButton(onClick={target=part;edited=part;error=""},modifier=Modifier.testTag("rename-part-$part")) {Text("改名")};TextButton(onClick={vm.savePartChoices(catalog-part)},modifier=Modifier.testTag("remove-part-$part")) {Text("移除")}
        }}
        val historical=snapshot.records.filter {it.type==RecordType.WORKOUT}.flatMap(WorkoutParts::of).distinct().filterNot {it in catalog}.sorted()
        if(historical.isNotEmpty()) Text("历史记录中的其他部位",style=MaterialTheme.typography.titleLarge)
        historical.forEach {part-> Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {Text(part,Modifier.weight(1f));TextButton(onClick={vm.addBodyPart(part)}) {Text("加入可选部位")}}}
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
    }
    if(modal) FullForm("管理训练部位",dismiss,content=content) else SubPage("管理训练部位",dismiss,content=content)
    target?.let {old->FullForm("部位改名",{target=null;error=""},actions={TextButton(onClick={runCatching {vm.renameBodyPart(old,edited);onRename(old,edited.trim());target=null;error="";notify("部位已改名")}.onFailure {error=it.message.orEmpty()}}) {Text("保存")}}) {
        TextFieldRow("部位名称",edited,{edited=it})
        Text("改名会同时更新全部历史训练和动作库中的对应部位。",style=MaterialTheme.typography.bodySmall)
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
    }}
    repair?.let {plan->FullForm("手臂归类修复预览",{repair=null},actions={TextButton(onClick={runCatching {vm.repairArmParts(plan);repair=null;notify("部位修复已保存")}.onFailure {error=it.message.orEmpty()}}) {Text("保存 ${plan.changes.size} 条")}}) {
        PartPreview(plan)
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
    }}
}

@Composable private fun PartPreview(plan:PartPlan) {
    plan.changes.forEach {change->val original=plan.originals.first {it.id==change.id};Panel(tint=PartTint) {
        Text(original.date.localText(),style=MaterialTheme.typography.titleMedium)
        Text("${names(WorkoutParts.of(original))} → ${names(change.bodyParts)}")
        Text(WorkoutCalendar.content(original),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }}
}

@Composable fun WorkoutPartAssistant(vm:AppViewModel,ids:Set<String>,focus:String?,dismiss:()->Unit,notify:(String)->Unit) {
    var input by rememberSaveable {mutableStateOf("")}
    var history by remember {mutableStateOf<List<JSONObject>>(emptyList())}
    var modelHistory by remember {mutableStateOf<List<JSONObject>>(emptyList())}
    var plan by remember {mutableStateOf<PartPlan?>(null)}
    var busy by remember {mutableStateOf(false)}
    var error by remember {mutableStateOf("")}
    val config by vm.config.collectAsState();val snapshot by vm.snapshot.collectAsState()
    val eligible=snapshot.records.any {it.type==RecordType.WORKOUT && it.id in ids && (focus==null || focus in WorkoutParts.of(it))}
    val scope=rememberCoroutineScope()
    FullForm("AI 调整训练部位",dismiss) {
        Text(focus?.let {"正在调整当前范围内「$it」分组的训练"} ?: "描述你想怎样调整当前范围的训练部位",style=MaterialTheme.typography.titleLarge)
        Text("AI 会先列出要改的记录和新部位。核对预览后点“应用修改”，才会写入训练记录。",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        if(!config.optBoolean("canWrite")) Text("请先开启“允许 AI 修改记录”。",color=MaterialTheme.colorScheme.error)
        Toggle("允许 AI 修改记录","",config.optBoolean("canWrite"),{runCatching {vm.setCoachWrites(it)}.onFailure {error=it.message.orEmpty()}})
        if(!eligible) Text("当前范围没有可调整的训练记录。")
        history.forEach {message->Panel(tint=if(message.optString("role")=="user") PartTint else MaterialTheme.colorScheme.primary) {Text(message.optString("content"))}}
        if(busy) CircularProgressIndicator(Modifier.size(24.dp))
        plan?.let {preview-> if(preview.changes.isNotEmpty()) {
            Text("修改预览",style=MaterialTheme.typography.titleLarge);PartPreview(preview)
            AppButton(onClick={runCatching {vm.applyWorkoutPartPlan(preview,ids,focus);plan=null;history=history+JSONObject().put("role","assistant").put("content","已保存 ${preview.changes.size} 条训练的部位修改。");notify("部位修改已保存")}.onFailure {error=it.message.orEmpty();plan=null}},enabled=!busy && config.optBoolean("canWrite")) {Text("应用 ${preview.changes.size} 条修改")}
        }}
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
        TextFieldRow("例如：把这条手臂训练改为二头、三头、小臂",input,{input=it},lines=2)
        AppButton(onClick={
            if(plan!=null) modelHistory=modelHistory+JSONObject().put("role","assistant").put("content","上一份预览被新请求替代，尚未保存。")
            val request=JSONObject().put("role","user").put("content",input.trim())
            history=history+request;modelHistory=modelHistory+request;input="";plan=null;error="";busy=true
            scope.launch {
                try {
                    val reply=vm.reviewWorkoutParts(modelHistory,ids,focus);plan=reply
                    history=history+JSONObject().put("role","assistant").put("content",reply.answer.ifBlank {if(reply.changes.isEmpty()) "没有需要应用的修改，请补充日期和部位。" else "请核对修改预览。"})
                    modelHistory=modelHistory+JSONObject().put("role","assistant").put("content",JSONObject().put("answer",reply.answer).put("changes",JSONArray(reply.changes.map {JSONObject().put("id",it.id).put("bodyParts",JSONArray(it.bodyParts))})).toString())
                } catch(e:CancellationException) {throw e}
                catch(e:Exception) {error="生成预览失败：${e.message.orEmpty()}"}
                finally {busy=false}
            }
        },enabled=!busy && eligible && config.optBoolean("canWrite") && input.isNotBlank()) {Text("发送")}
    }
}
