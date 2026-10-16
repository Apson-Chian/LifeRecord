package ltd.apsonchian.liferecord.ui

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.*
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.R
import ltd.apsonchian.liferecord.data.CoachIdentity

@Composable fun CoachAvatar(identity: CoachIdentity, size: Dp = 32.dp) {
    val bitmap=remember(identity.avatar) {identity.avatar?.let {BitmapFactory.decodeByteArray(it,0,it.size)}}
    DisposableEffect(bitmap) {onDispose {bitmap?.recycle()}}
    val modifier=Modifier.size(size).clip(CircleShape).border(1.dp,androidx.compose.ui.graphics.Color.White.copy(alpha=.75f),CircleShape)
    if(bitmap!=null) Image(bitmap.asImageBitmap(),null,modifier,contentScale=ContentScale.Crop)
    else Image(painterResource(R.drawable.coach_avatar),null,modifier,contentScale=ContentScale.Crop)
}

@Composable fun CoachProfile(vm: AppViewModel, dismiss: () -> Unit, notify: (String) -> Unit) {
    val current by vm.coachIdentity.collectAsState()
    var name by rememberSaveable {mutableStateOf(current.name)}
    var avatar by remember {mutableStateOf(current.avatar)}
    var loading by remember {mutableStateOf(false)}
    var error by remember {mutableStateOf("")}
    val scope=rememberCoroutineScope()
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) {uri -> if(uri!=null) scope.launch {
        loading=true
        try {avatar=withContext(Dispatchers.IO) {vm.app.photos.readAvatar(uri)};error=""}
        catch(e: CancellationException) {throw e}
        catch(e: Exception) {error=e.message.orEmpty()}
        finally {loading=false}
    }}
    val valid=runCatching {CoachIdentity.validated(name,avatar)}.isSuccess
    FullForm("自定义教练",dismiss,actions={TextButton(onClick={runCatching {vm.saveCoachIdentity(name,avatar);dismiss();notify("教练资料已保存")}.onFailure {error=it.message.orEmpty()}},enabled=valid && !loading) {Text("保存")}}) {
        Column(Modifier.fillMaxWidth().padding(vertical=12.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(14.dp)) {
            CoachAvatar(CoachIdentity(name,avatar),96.dp)
            TextButton(onClick={picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))},enabled=!loading) {Text(if(loading) "正在读取照片…" else "从相册更换头像")}
            if(loading) CircularProgressIndicator(Modifier.size(24.dp))
            if(avatar!=null) TextButton(onClick={avatar=null},enabled=!loading) {Text("使用默认头像")}
        }
        TextFieldRow("聊天 AI 名称",name,{name=it})
        Text("${name.trim().codePointCount(0,name.trim().length)}/30",style=MaterialTheme.typography.bodySmall,color=if(valid) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error)
        Text("名称和头像会应用到所有教练对话，仅保存在这台设备上。",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
        SoftButton(onClick={name="AI 助手";avatar=null},enabled=!loading) {Text("恢复默认名称和头像")}
        if(error.isNotBlank()) Text(error,color=MaterialTheme.colorScheme.error)
    }
}
