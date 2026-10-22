package ltd.apsonchian.liferecord.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.BodyTrend
import java.time.LocalDate
import kotlin.math.sin

@Composable fun Onboarding(vm: AppViewModel) {
    var step by rememberSaveable { mutableIntStateOf(0) }
    var examples by rememberSaveable { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val titles = listOf("从今天的一餐开始", "让记录，慢慢连成变化", "有问题，和教练聊聊", "按你的节奏开始")
    val descriptions = listOf(
        "饮食、训练和身体测量，都放在「今日」。先记一项就好，不必一次填完。",
        "在「趋势」回看热量、训练与身体变化。切换时间范围，也能点进每一天的明细。",
        "聊饮食、训练，或请教练整理已有记录。使用 AI 需要联网和可用的服务。",
        "直接记录自己的生活，或先用一份完整示例熟悉功能。之后都能在设置中重看导览。"
    )
    fun finish(loadExamples: Boolean) {
        runCatching { if(loadExamples) vm.seedDemo(); vm.completeOnboarding() }
            .onFailure { error = it.message ?: "请重试，或选择从自己的第一条开始。" }
    }
    BackHandler(step > 0) { step-- }
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).systemBarsPadding(),horizontalAlignment=Alignment.CenterHorizontally) {
        Row(Modifier.widthIn(max=608.dp).fillMaxWidth().padding(horizontal=24.dp),verticalAlignment=Alignment.CenterVertically) {
            if(step > 0) TextButton(onClick={step--}) { Text("上一步") }
            else Text("LifeRecord",style=MaterialTheme.typography.titleMedium)
            Spacer(Modifier.weight(1f))
            TextButton(onClick={finish(false)},modifier=Modifier.testTag("onboarding-skip")) {Text("跳过")}
        }
        Row(Modifier.widthIn(max=608.dp).fillMaxWidth().padding(horizontal=24.dp).semantics(mergeDescendants=true) { contentDescription="使用导览，第 ${step+1} 步，共 4 步" },horizontalArrangement=Arrangement.spacedBy(6.dp)) {
            repeat(4) { index -> Box(Modifier.weight(1f).height(4.dp).background(if(index<=step) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha=.1f),RoundedCornerShape(50))) }
        }
        key(step) {
            Column(Modifier.weight(1f).widthIn(max=608.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
                Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
                    Text(listOf("01 / 轻松记录", "02 / 看见变化", "03 / 智能教练", "04 / 准备好了")[step],style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.primary)
                    Text(titles[step],Modifier.semantics { heading() }.testTag("onboarding-title"),style=MaterialTheme.typography.headlineLarge)
                    Text(descriptions[step],style=MaterialTheme.typography.bodyLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
                when(step) {
                    0 -> {
                        Panel {
                            PreviewTitle("今日的一小步")
                            PreviewRow(Glyph.Meal,"燕麦鸡蛋牛奶碗","早餐 · 527 kcal",Color(0xFFFF9500))
                            HorizontalDivider()
                            PreviewRow(Glyph.Workout,"胸部 · 三头","45 分钟 · 2 个动作",Color(0xFF31B8C4))
                            HorizontalDivider()
                            PreviewRow(Glyph.Weight,"晨起测量","65.0 kg · 体脂 14.3%",MaterialTheme.colorScheme.primary)
                        }
                        OnboardingTip(Glyph.Plus,"记一餐或一次测量","点今日页右上角的「＋」，手动填写即可保存。")
                        OnboardingTip(Glyph.Workout,"训练可以先计时","结束后再补部位、动作、重量和次数。")
                    }
                    1 -> {
                        Panel {
                            PreviewTitle("一个月的记录")
                            Text("体重有波动，变化看趋势",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
                            val points=remember { (0..13).map { BodyTrend.Point(LocalDate.now().minusDays(13L-it),64+it*.07+sin(it.toDouble())*.12,64+it*.07,1) } }
                            TrendChart(points,"kg",MaterialTheme.colorScheme.primary,inspectionControls=false)
                            Text("每日热量 · 训练日历 · 每日明细",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        OnboardingTip(Glyph.Calendar,"从概览走到明细","点开图表或训练日历，查看每一天发生了什么。")
                        OnboardingTip(Glyph.Trend,"空白不等于零","缺少记录的日期会留空，不会当作零摄入或零体重。")
                    }
                    2 -> {
                        Panel {
                            PreviewTitle("智能教练")
                            Text("这周的训练记录在哪里看？",Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.primary.copy(alpha=.08f),RoundedCornerShape(16.dp)).padding(14.dp),style=MaterialTheme.typography.bodyLarge)
                            Text("到「趋势」打开训练日历，选择日期，就能查看训练部位、动作和每组明细。",Modifier.background(MaterialTheme.colorScheme.onSurface.copy(alpha=.04f),RoundedCornerShape(16.dp)).padding(14.dp),style=MaterialTheme.typography.bodyMedium)
                            Text("预先编写的对话展示，无需连接 AI",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        OnboardingTip(Glyph.Shield,"由你决定是否修改记录","需要教练操作记录时，先开启记录权限，并留意操作与复核提示。")
                        OnboardingTip(Glyph.Archive,"日常记录可离线使用","启用同步或发起 AI 请求时，相关数据才会发送至配置的服务。")
                    }
                    else -> {
                        Column(verticalArrangement=Arrangement.spacedBy(12.dp),modifier=Modifier.selectableGroup()) {
                            StartChoice(!examples,Glyph.Compose,"从自己的第一条开始","保留现有内容，不添加示例。","onboarding-blank") {examples=false}
                            StartChoice(examples,Glyph.Trend,"先体验完整示例","近 30 天饮食、身体测量、训练与两组教练对话；可随时清除。","onboarding-examples") {examples=true}
                        }
                        OnboardingTip(Glyph.Target,"进入后，先设自己的目标","到「设置 → 个人与目标」调整体重与每日营养目标。")
                        Text("示例为合成内容，仅保存在本机；不计入真实目标反馈、提醒或 AI 周报，也不会同步。清除示例会保留你自己的记录。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        Surface(color=MaterialTheme.colorScheme.surface) {
            Column(Modifier.widthIn(max=608.dp).fillMaxWidth().padding(horizontal=24.dp,vertical=16.dp),verticalArrangement=Arrangement.spacedBy(8.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                AppButton(onClick={if(step<3) step++ else finish(examples)},modifier=Modifier.fillMaxWidth().heightIn(min=54.dp).testTag("onboarding-continue")) {
                    Text(if(step<3) "继续" else if(examples) "载入示例，开始体验" else "开始我的记录")
                }
                Text(if(step==3) "无需现在登录或配置接口" else "${step+1} / 4 · 随时可以跳过",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    error?.let { message -> GlassAlertDialog(onDismissRequest={error=null},title={Text("暂时无法开始")},text={Text(message)},confirmButton={TextButton(onClick={error=null}) {Text("好")}}) }
}

@Composable private fun PreviewTitle(title:String) {
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
        Text(title,Modifier.weight(1f),style=MaterialTheme.typography.titleMedium)
        Text("示意",Modifier.background(MaterialTheme.colorScheme.onSurface.copy(alpha=.05f),RoundedCornerShape(50)).padding(horizontal=8.dp,vertical=4.dp),style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable private fun PreviewRow(glyph:Glyph,title:String,detail:String,color:Color) {
    Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
        IconBadge(glyph,color)
        Column(verticalArrangement=Arrangement.spacedBy(4.dp)) {Text(title,style=MaterialTheme.typography.titleSmall);Text(detail,style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
    }
}
@Composable private fun OnboardingTip(glyph:Glyph,title:String,detail:String) {
    Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        AppIcon(glyph,MaterialTheme.colorScheme.primary,Modifier.size(24.dp))
        Column(verticalArrangement=Arrangement.spacedBy(5.dp)) {Text(title,style=MaterialTheme.typography.titleSmall);Text(detail,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)}
    }
}
@Composable private fun StartChoice(selected:Boolean,glyph:Glyph,title:String,detail:String,tag:String,onClick:()->Unit) {
    val color=MaterialTheme.colorScheme.primary
    Row(Modifier.fillMaxWidth().background(if(selected) color.copy(alpha=.08f) else MaterialTheme.colorScheme.surface,RoundedCornerShape(20.dp))
        .border(1.dp,if(selected) color else MaterialTheme.colorScheme.outline.copy(alpha=.2f),RoundedCornerShape(20.dp))
        .selectable(selected=selected,role=Role.RadioButton,onClick=onClick).testTag(tag).padding(18.dp),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        AppIcon(glyph,color,Modifier.size(28.dp))
        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)) {Text(title,style=MaterialTheme.typography.titleMedium);Text(detail,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)}
        RadioButton(selected=selected,onClick=null,modifier=Modifier.size(24.dp))
    }
}
