package ltd.apsonchian.liferecord.service

import android.content.Context
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import androidx.exifinterface.media.ExifInterface

class Photos(private val context: Context) {
    private val local = File(context.filesDir, "meal-photos").apply { mkdirs() }
    private val chat = File(context.filesDir, "chat-photos").apply { mkdirs() }
    private val cache = File(context.cacheDir, "private-photos").apply { mkdirs() }
    fun read(uri: Uri): ByteArray {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, options) }
        require(options.outWidth > 0) { "无法读取图片" }
        options.inJustDecodeBounds = false
        while(maxOf(options.outWidth, options.outHeight) / options.inSampleSize.coerceAtLeast(1) > 2000) options.inSampleSize = options.inSampleSize.coerceAtLeast(1) * 2
        val bitmap = context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, options) } ?: error("无法解码图片")
        val orientation = context.contentResolver.openInputStream(uri).use { stream -> if(stream != null) ExifInterface(stream).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) else ExifInterface.ORIENTATION_NORMAL }
        val matrix = Matrix().apply { when(orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { postRotate(90f); postScale(-1f,1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { postRotate(270f); postScale(-1f,1f) }
        } }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        val longest = maxOf(rotated.width, rotated.height)
        val scaled = if(longest > 1600) Bitmap.createScaledBitmap(rotated, rotated.width*1600/longest, rotated.height*1600/longest, true) else rotated
        return ByteArrayOutputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, 82, it); val bytes = it.toByteArray(); if(scaled !== rotated) scaled.recycle(); if(rotated !== bitmap) rotated.recycle(); bitmap.recycle(); bytes }
    }
    /** Publish only after the whole JPEG is written; no gallery permission on API 29+. */
    fun saveToGallery(bytes: ByteArray): Uri {
        require(Build.VERSION.SDK_INT >= 29) { "旧版系统请使用系统文件保存窗口" }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "无法保存无效图片" }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "LifeRecord-${java.util.UUID.randomUUID()}.jpg")
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/LifeRecord")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),values) ?: error("无法创建相册照片")
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("无法写入照片")
            check(resolver.update(uri,ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING,0) },null,null) == 1) { "无法完成照片保存" }
            return uri
        } catch(e: Exception) { resolver.delete(uri,null,null); throw e }
    }
    fun save(bytes: ByteArray): String = java.util.UUID.randomUUID().toString().let { name -> File(local, "$name.jpg").writeBytes(bytes); "$name.jpg" }
    fun saveChat(bytes: ByteArray): String {
        val file = File(chat, "${java.util.UUID.randomUUID()}.jpg")
        try { file.writeBytes(bytes); return file.name }
        catch(e: Exception) { file.delete(); throw e }
    }
    fun chat(name: String): ByteArray { require(name.matches(Regex("[0-9a-f-]+\\.jpg"))); return File(chat, name).readBytes() }
    fun deleteChat(name: String) { require(name.matches(Regex("[0-9a-f-]+\\.jpg"))); File(chat, name).delete() }
    fun local(name: String): ByteArray { require(name.matches(Regex("[0-9a-f-]+\\.jpg"))); return File(local, name).readBytes() }
    fun remote(id: String, key: String, network: Network): ByteArray {
        val scope = MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).joinToString("") { "%02x".format(it) }
        require(id.matches(Regex("[0-9a-f]{32}")))
        val file = File(cache, "$scope-$id.jpg")
        if(file.exists()) { file.setLastModified(System.currentTimeMillis()); return file.readBytes() }
        return network.photo(id, key).also { bytes ->
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            require(bounds.outWidth > 0 && bounds.outHeight > 0) { "服务器未返回有效图片" }
            file.writeBytes(bytes)
            var total = cache.listFiles().orEmpty().sumOf { it.length() }
            cache.listFiles().orEmpty().sortedBy { it.lastModified() }.forEach { if(total > 128*1024*1024) { total -= it.length(); it.delete() } }
        }
    }
}
