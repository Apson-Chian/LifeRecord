package ltd.apsonchian.liferecord.ui

import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.*
import ltd.apsonchian.liferecord.AppViewModel
import ltd.apsonchian.liferecord.data.*

internal class GalleryPhoto(val key: String, val load: suspend () -> ByteArray)
internal fun recordGallery(vm: AppViewModel, record: Record): List<GalleryPhoto> {
    val locals = record.json.optJSONArray("localPhotoFiles")?.strings().orEmpty()
    val remotes = record.json.optJSONArray("photoIDs")?.strings().orEmpty().drop(record.json.optJSONArray("uploadedPhotoFiles")?.length() ?: 0)
    return locals.map { id -> GalleryPhoto("local:$id") { vm.photo(record, id, true) } } +
        remotes.map { id -> GalleryPhoto("remote:$id") { vm.photo(record, id, false) } }
}

/** Compatibility entry point for a single in-memory photo. */
@Composable fun PhotoViewer(vm: AppViewModel, data: ByteArray, dismiss: () -> Unit) {
    val photos = remember(data) { listOf(GalleryPhoto("single") { data }) }
    PhotoGallery(vm, photos, 0, dismiss)
}

@Composable internal fun PhotoGallery(vm: AppViewModel, photos: List<GalleryPhoto>, initial: Int, dismiss: () -> Unit) {
    if (photos.isEmpty()) return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pager = rememberPagerState(initialPage = initial.coerceIn(photos.indices), pageCount = { photos.size })
    var zoomed by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var notice by rememberSaveable { mutableStateOf("") }
    var documentBytes by remember { mutableStateOf<ByteArray?>(null) }
    val feedback = rememberActionFeedback()
    val document = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("image/jpeg")) { uri ->
        val bytes = documentBytes
        if (uri != null && bytes != null) scope.launch {
            saving = true
            try {
                withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("无法写入照片") }
                notice = "照片已保存"; feedback(true)
            } catch (e: Exception) { notice = "保存失败：${e.message.orEmpty()}"; feedback(false) }
            finally { saving = false; documentBytes = null }
        } else documentBytes = null
    }
    LaunchedEffect(pager.currentPage) { zoomed = false; notice = "" }
    Dialog(onDismissRequest = dismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black).testTag("photo-viewer")) {
            HorizontalPager(state = pager, modifier = Modifier.fillMaxSize(), beyondViewportPageCount = 1,
                userScrollEnabled = !zoomed, key = { photos[it].key }) { page ->
                if (kotlin.math.abs(page - pager.currentPage) <= 1) {
                    GalleryPage(photos[page], "第 ${page + 1} 张，共 ${photos.size} 张照片", page == pager.currentPage, { if (page == pager.currentPage) zoomed = it }, dismiss)
                }
            }
            Row(Modifier.align(Alignment.TopCenter).fillMaxWidth().statusBarsPadding().background(Color.Black.copy(alpha = .55f)).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = dismiss) { Icon(Icons.Default.Close, "关闭照片", tint = Color.White) }
                Text("${pager.currentPage + 1} / ${photos.size}", Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Polite }, color = Color.White)
                TextButton(enabled = !saving, onClick = {
                    val current = photos[pager.currentPage]
                    scope.launch {
                        saving = true
                        try {
                            val bytes = withContext(Dispatchers.IO) { current.load() }
                            if (Build.VERSION.SDK_INT < 29) { documentBytes = bytes; document.launch("LifeRecord-${System.currentTimeMillis()}.jpg") }
                            else { withContext(Dispatchers.IO) { vm.app.photos.saveToGallery(bytes) }; notice = "已保存到系统相册"; feedback(true) }
                        } catch (e: CancellationException) { throw e }
                        catch (e: Exception) { notice = "保存失败：${e.message.orEmpty()}"; feedback(false) }
                        finally { saving = false }
                    }
                }) { Text(if (saving) "保存中…" else "保存到相册", color = Color.White) }
            }
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Color.Black.copy(alpha = .6f)).navigationBarsPadding()) {
                if (notice.isNotBlank()) Text(notice, Modifier.padding(horizontal = 20.dp, vertical = 8.dp).semantics { liveRegion = LiveRegionMode.Polite }, color = Color.White)
                if (photos.size > 1) Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(enabled = pager.currentPage > 0 && !zoomed, onClick = { scope.launch { pager.animateScrollToPage(pager.currentPage - 1) } }) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "上一张照片", tint = if (pager.currentPage > 0 && !zoomed) Color.White else Color.Gray)
                    }
                    Text(if (zoomed) "双击还原后切换照片" else "左右切换 · 下滑关闭 · 双指缩放", Modifier.weight(1f), color = Color.White, style = MaterialTheme.typography.bodySmall)
                    IconButton(enabled = pager.currentPage < photos.lastIndex && !zoomed, onClick = { scope.launch { pager.animateScrollToPage(pager.currentPage + 1) } }) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "下一张照片", tint = if (pager.currentPage < photos.lastIndex && !zoomed) Color.White else Color.Gray)
                    }
                }
            }
        }
    }
}

@Composable private fun GalleryPage(photo: GalleryPhoto, description: String, active: Boolean, onZoom: (Boolean) -> Unit, dismiss: () -> Unit) {
    var bytes by remember(photo.key) { mutableStateOf<ByteArray?>(null) }
    var error by remember(photo.key) { mutableStateOf("") }
    var retry by remember { mutableIntStateOf(0) }
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var swipe by remember { mutableFloatStateOf(0f) }
    var extent by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }
    val threshold = with(LocalDensity.current) { 96.dp.toPx() }
    val aspect = remember(bytes) {
        bytes?.let {data -> android.graphics.BitmapFactory.Options().apply {inJustDecodeBounds=true}.let {bounds ->
            android.graphics.BitmapFactory.decodeByteArray(data,0,data.size,bounds)
            if(bounds.outHeight>0) bounds.outWidth.toFloat()/bounds.outHeight else 1f
        }} ?: 1f
    }
    LaunchedEffect(photo.key, retry) {
        error = ""
        try { bytes = withContext(Dispatchers.IO) { photo.load() } }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = "照片加载失败：${e.message.orEmpty()}" }
    }
    LaunchedEffect(active) { if (!active) { scale = 1f; offset = Offset.Zero; swipe = 0f } }
    LaunchedEffect(scale, active) { if (active) onZoom(scale > 1f) }
    Box(Modifier.fillMaxSize().onSizeChanged { extent = it }.semantics {
            contentDescription = description
            stateDescription = if(scale>1f) "已放大 ${format(scale.toDouble())} 倍" else "原始比例"
            customActions = listOf(
                CustomAccessibilityAction("放大照片") { scale=2f;offset=Offset.Zero;true },
                CustomAccessibilityAction("还原照片") { scale=1f;offset=Offset.Zero;true }
            )
        }
        .transformable(rememberTransformableState { zoom, pan, _ ->
            scale = (scale * zoom).coerceIn(1f, 5f)
            val fittedWidth = minOf(extent.width.toFloat(), extent.height * aspect)
            val fittedHeight = minOf(extent.height.toFloat(), extent.width / aspect)
            val maxX = ((fittedWidth * scale - extent.width) / 2f).coerceAtLeast(0f)
            val maxY = ((fittedHeight * scale - extent.height) / 2f).coerceAtLeast(0f)
            offset = if (scale > 1f) Offset((offset.x + pan.x).coerceIn(-maxX, maxX), (offset.y + pan.y).coerceIn(-maxY, maxY)) else Offset.Zero
        }, canPan = { scale > 1f })
        .pointerInput(photo.key) { detectTapGestures(onDoubleTap = { scale = if (scale > 1f) 1f else 2f; offset = Offset.Zero }) }
        .pointerInput(scale) {
            if (scale <= 1f) detectVerticalDragGestures(onVerticalDrag = { change, delta -> change.consume(); swipe = (swipe + delta).coerceAtLeast(0f) },
                onDragEnd = { if (swipe > threshold) dismiss() else swipe = 0f }, onDragCancel = { swipe = 0f })
        }, contentAlignment = Alignment.Center) {
        bytes?.let { PhotoBytes(it, Modifier.fillMaxSize().graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y + swipe }, androidx.compose.ui.layout.ContentScale.Fit,maxDimension=2000) }
            ?: if (error.isBlank()) CircularProgressIndicator() else TextButton(onClick = { retry++ }) { Text("$error，点此重试", color = Color.White) }
    }
}
