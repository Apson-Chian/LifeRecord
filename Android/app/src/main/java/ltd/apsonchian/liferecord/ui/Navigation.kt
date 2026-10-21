@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package ltd.apsonchian.liferecord.ui

import androidx.activity.compose.BackHandler
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*
import java.time.LocalDate
import java.time.YearMonth

@Composable fun RangePicker(selected:Int, change:(Int)->Unit) {
    ChoiceControl(listOf("7" to "近 7 天", "30" to "近 30 天", "0" to "全部"), selected.toString(), { change(it.toInt()) })
}

@Composable fun RecordCalendar(selected:LocalDate, records:List<Record>, dismiss:()->Unit, select:(LocalDate)->Unit) {
    var monthText by rememberSaveable { mutableStateOf(YearMonth.from(selected).toString()) }
    val month=YearMonth.parse(monthText)
    val recorded=records.filter { it.type in listOf(RecordType.MEAL,RecordType.BODY,RecordType.WORKOUT) }.map { it.date.day() }.toSet()
    ModalBottomSheet(onDismissRequest=dismiss) {
        Column(Modifier.fillMaxWidth().padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                TextButton(onClick={monthText=month.minusMonths(1).toString()}) { Text("上个月") }
                Text("${month.year} 年 ${month.monthValue} 月",style=MaterialTheme.typography.titleMedium,modifier=Modifier.weight(1f))
                TextButton(onClick={monthText=month.plusMonths(1).toString()}) { Text("下个月") }
            }
            Row { listOf("一","二","三","四","五","六","日").forEach { Text(it,modifier=Modifier.weight(1f),textAlign=androidx.compose.ui.text.style.TextAlign.Center,color=MaterialTheme.colorScheme.onSurfaceVariant) } }
            val offset=month.atDay(1).dayOfWeek.value-1
            val weeks=(offset+month.lengthOfMonth()+6)/7
            repeat(weeks) { week -> Row(Modifier.fillMaxWidth()) {
                repeat(7) { weekday ->
                    val number=week*7+weekday-offset+1
                    if(number !in 1..month.lengthOfMonth()) Spacer(Modifier.weight(1f).height(48.dp)) else {
                        val day=month.atDay(number)
                        Column(Modifier.weight(1f).heightIn(min=48.dp).clip(RoundedCornerShape(12.dp))
                            .background(if(day==selected) MaterialTheme.colorScheme.primary.copy(alpha=.12f) else Color.Transparent)
                            .clickable { select(day); dismiss() }.padding(vertical=8.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                            Text(number.toString(),color=if(day==selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
                            Spacer(Modifier.height(4.dp))
                            Box(Modifier.size(4.dp).background(if(day in recorded) Color(0xFF29AD5E) else Color.Transparent,RoundedCornerShape(50)))
                        }
                    }
                }
            } }
            Text("绿点表示已有餐食、身体测量或训练记录",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick={select(LocalDate.now());dismiss()},modifier=Modifier.align(Alignment.CenterHorizontally)) { Text("回到今天") }
            Spacer(Modifier.navigationBarsPadding())
        }
    }
}

@Composable fun MealHistory(vm:AppViewModel,s:Snapshot,photosOnly:Boolean,dismiss:()->Unit,detail:(Record)->Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    val meals=s.records.filter { it.type==RecordType.MEAL &&
        (!photosOnly || it.json.optJSONArray("localPhotoFiles")?.length().orZero()>0 || it.json.optJSONArray("photoIDs")?.length().orZero()>0) &&
        (query.isBlank() || it.title.contains(query,true) || it.json.optString("note").contains(query,true)) }.sortedByDescending { it.date }
    LazyFullForm(if(photosOnly) "餐食照片" else "餐食记录",dismiss) {
        item("search") { OutlinedTextField(query,{query=it},Modifier.fillMaxWidth(),label={Text("搜索餐食与备注")},singleLine=true) }
        if(meals.isEmpty()) item("empty") { Empty("没有符合条件的餐食",if(photosOnly) "添加照片后会显示在这里" else "记录一餐，或调整搜索内容") }
        meals.forEach { r ->
        item("record:${r.id}") { Panel {
            Text(r.date.localText(),style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            RecordRow(r) { detail(r) }
        } }
        if (photosOnly) {
            recordGallery(vm,r).forEach { photo ->
                item("${r.id}:${photo.key}") {
                    PhotoRecord(vm,r,photo.key.substringAfter(":"),photo.key.startsWith("local:"))
                }
            }
        }
        }
    }
}
private fun Int?.orZero()=this ?: 0

/** A navigation destination inside its tab; the floating navigation remains available. */
@Composable fun SubPage(title:String,dismiss:()->Unit,actions:@Composable RowScope.()->Unit={},content:@Composable ColumnScope.()->Unit) {
    BackHandler { dismiss() }
    Column(Modifier.fillMaxSize().imePadding()) {
        CenterAlignedTopAppBar(title={Text(title,style=MaterialTheme.typography.titleLarge)},navigationIcon={IconButton(onClick=dismiss) { AppIcon(Glyph.Chevron,MaterialTheme.colorScheme.primary,Modifier.size(20.dp).graphicsLayer {rotationZ=180f},"返回") }},actions=actions,colors=TopAppBarDefaults.topAppBarColors(containerColor=Color.Transparent))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start=16.dp,end=16.dp,top=16.dp,bottom=glassPageBottomPadding()),verticalArrangement=Arrangement.spacedBy(16.dp),content=content)
    }
}

@Composable internal fun LazySubPage(title:String,dismiss:()->Unit,actions:@Composable RowScope.()->Unit={},content:androidx.compose.foundation.lazy.LazyListScope.()->Unit) {
    BackHandler { dismiss() }
    Column(Modifier.fillMaxSize().imePadding()) {
        CenterAlignedTopAppBar(title={Text(title,style=MaterialTheme.typography.titleLarge)},navigationIcon={IconButton(onClick=dismiss) { AppIcon(Glyph.Chevron,MaterialTheme.colorScheme.primary,Modifier.size(20.dp).graphicsLayer {rotationZ=180f},"返回") }},actions=actions,colors=TopAppBarDefaults.topAppBarColors(containerColor=Color.Transparent))
        androidx.compose.foundation.lazy.LazyColumn(Modifier.weight(1f).fillMaxWidth(),contentPadding=PaddingValues(start=16.dp,end=16.dp,top=16.dp,bottom=glassPageBottomPadding()),verticalArrangement=Arrangement.spacedBy(16.dp),content=content)
    }
}
