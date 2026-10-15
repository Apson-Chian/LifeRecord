package ltd.apsonchian.liferecord.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.AppViewModel

/** Uses the system camera and picker; only the temporary capture directory is shared. */
@Composable fun PhotoInput(vm: AppViewModel, photos: List<ByteArray>, maxCount: Int = 12, enabled: Boolean = true, change: (List<ByteArray>) -> Unit, notify: (String) -> Unit, button: @Composable (() -> Unit) -> Unit) {
    var menu by remember {mutableStateOf(false)}
    var reading by remember {mutableStateOf(false)}
    var capture by rememberSaveable {mutableStateOf<String?>(null)}
    val scope=rememberCoroutineScope()
    val currentPhotos by rememberUpdatedState(photos);val currentChange by rememberUpdatedState(change)
    fun add(uris: List<Uri>, temporary: Boolean = false) {
        scope.launch {
            reading=true
            try {
                require(currentPhotos.size+uris.size<=maxCount.coerceIn(1,12)) {"最多选择 ${maxCount.coerceIn(1,12)} 张照片"}
                val added=withContext(Dispatchers.IO) {vm.readPhotos(uris)}
                currentChange(currentPhotos+added)
            } catch(e: CancellationException) {throw e}
            catch(e: Exception) {notify(e.message ?: "无法读取照片")}
            finally {if(temporary) uris.forEach {runCatching {vm.app.photos.discardCapture(it)}};reading=false}
        }
    }
    val camera=rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) {success ->
        capture?.let {raw -> val uri=Uri.parse(raw);if(success) add(listOf(uri),true) else runCatching {vm.app.photos.discardCapture(uri)} };capture=null
    }
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(12)) {if(it.isNotEmpty()) add(it)}
    Box {
        button {if(enabled && !reading) menu=true}
        DropdownMenu(menu,{menu=false}) {
            DropdownMenuItem(text={Text("拍照")},onClick={menu=false;runCatching {val uri=vm.app.photos.captureUri();capture=uri.toString();camera.launch(uri)}.onFailure {capture?.let {runCatching {vm.app.photos.discardCapture(Uri.parse(it))}};capture=null;notify("无法打开系统相机")}})
            DropdownMenuItem(text={Text("从相册选择")},onClick={menu=false;picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))})
        }
    }
}
