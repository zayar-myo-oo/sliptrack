package app.sliptrack.sliptrack

import android.Manifest
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.work.*
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MediaBridge(private val activity: FlutterFragmentActivity, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val channel = MethodChannel(messenger, "app.sliptrack/media")
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val resolver get() = activity.contentResolver
    private val preferences = activity.getSharedPreferences("sliptrack.media", 0)
    private var sink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private var pickerResult: MethodChannel.Result? = null
    private var backupResult: MethodChannel.Result? = null
    private var backupData: String? = null
    private val incoming = mutableListOf<String>()
    private var observing = false
    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { if (preferences.getBoolean("automatic", false)) sink?.success(true) }
    }
    private val permissions = activity.registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        permissionResult?.success(permission()); permissionResult = null; updateObserver()
    }
    private val picker = activity.registerForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(20)) { uris ->
        uris.forEach { uri ->
            try { resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: SecurityException) { }
        }
        pickerResult?.success(uris.map { it.toString() }); pickerResult = null
    }
    private val saveBackup = activity.registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val callback = backupResult; val data = backupData; backupResult = null; backupData = null
        if (callback != null) {
            if (uri == null || data == null) callback.success(null)
            else background(callback) { resolver.openOutputStream(uri)?.use { it.write(data.toByteArray(Charsets.UTF_8)) } ?: throw IllegalStateException(); true }
        }
    }
    private val openBackup = activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val callback = backupResult; backupResult = null
        if (callback != null) {
            if (uri == null) callback.success(null)
            else background(callback) { resolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: throw IllegalStateException() }
        }
    }
    init {
        channel.setMethodCallHandler(::handle)
        EventChannel(messenger, "app.sliptrack/media_changes").setStreamHandler(this)
        updateObserver()
    }
    fun receive(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("image/") != true) return
        val uri = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else @Suppress("DEPRECATION") (intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
        if (uri != null && uri.scheme == "content") {
            incoming.add(uri.toString()); sink?.success(true)
        }
    }
    private fun permission(): String {
        fun granted(value: String) = ContextCompat.checkSelfPermission(activity, value) == PackageManager.PERMISSION_GRANTED
        return when {
            Build.VERSION.SDK_INT >= 33 && granted(Manifest.permission.READ_MEDIA_IMAGES) -> "full"
            Build.VERSION.SDK_INT >= 34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> "limited"
            Build.VERSION.SDK_INT < 33 && granted(Manifest.permission.READ_EXTERNAL_STORAGE) -> "full"
            else -> "denied"
        }
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "backupExport", "backupImport" -> {
                if (backupResult != null) { result.error("busy", "File picker open", null); return }
                backupResult = result
                if (call.method == "backupExport") { backupData = call.argument<String>("data"); saveBackup.launch("sliptrack-backup.json") }
                else openBackup.launch(arrayOf("application/json", "application/octet-stream"))
            }
            "permission" -> {
                if (call.argument<Boolean>("request") == true) {
                    if (permissionResult != null) { result.error("busy", "Permission request pending", null); return }
                    permissionResult = result
                    permissions.launch(when {
                        Build.VERSION.SDK_INT >= 34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                        Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
                        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
                    })
                } else { result.success(permission()); updateObserver() }
            }
            "pick" -> {
                if (pickerResult != null) { result.error("busy", "Picker open", null); return }
                pickerResult = result; picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }
            "incoming" -> { result.success(incoming.toList()); incoming.clear() }
            "cleanup" -> result.success(null) // Never delete a source image from the library.
            "limitedPicker" -> {
                if (permissionResult != null) { result.error("busy", "Permission request pending", null); return }
                permissionResult = result
                if (Build.VERSION.SDK_INT >= 34) permissions.launch(arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED))
                else { permissionResult = null; result.success(null) }
            }
            "automatic" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                preferences.edit().putBoolean("automatic", enabled).apply(); updateObserver()
                if (enabled && permission() == "full") {
                    val work = PeriodicWorkRequestBuilder<GalleryCatchUpWorker>(15, TimeUnit.MINUTES)
                        .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build()).build()
                    WorkManager.getInstance(activity).enqueueUniquePeriodicWork("sliptrack.gallery", ExistingPeriodicWorkPolicy.UPDATE, work)
                } else WorkManager.getInstance(activity).cancelUniqueWork("sliptrack.gallery")
                result.success(null)
            }
            "assets" -> background(result) {
                if (permission() == "denied") throw SecurityException()
                val after = (call.argument<Number>("afterMs")?.toLong() ?: 0L) / 1000
                val since = call.argument<Number>("sinceMs")?.toLong() ?: 0L
                val offset = call.argument<Number>("offset")?.toInt() ?: 0
                val ids = mutableListOf<String>()
                resolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Images.Media._ID),
                    "${MediaStore.Images.Media.DATE_ADDED} >= ? AND COALESCE(NULLIF(${MediaStore.Images.Media.DATE_TAKEN},0),${MediaStore.Images.Media.DATE_ADDED}*1000) >= ?",
                    arrayOf(after.toString(), since.toString()), "${MediaStore.Images.Media._ID} ASC")?.use { cursor ->
                    if (cursor.moveToPosition(offset)) do {
                        ids.add(ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cursor.getLong(0)).toString())
                    } while (ids.size < 100 && cursor.moveToNext())
                }
                ids
            }
            "thumbnail" -> background(result) {
                val uri = authorizedUri(call)
                val bitmap = if (Build.VERSION.SDK_INT >= 29) resolver.loadThumbnail(uri, Size(1200, 1600), null)
                else {
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    resolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, bounds) }
                    val options = BitmapFactory.Options().apply { inSampleSize = maxOf(1, maxOf(bounds.outWidth, bounds.outHeight) / 1600) }
                    resolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, options) } ?: throw IllegalStateException()
                }
                val bytes = ByteArrayOutputStream(); bitmap.compress(Bitmap.CompressFormat.JPEG, 85, bytes); bitmap.recycle(); bytes.toByteArray()
            }
            "ocr" -> {
                executor.execute {
                    try {
                        val uri = authorizedUri(call)
                        val digest = MessageDigest.getInstance("SHA-256")
                        resolver.openInputStream(uri)?.use { input ->
                            val buffer = ByteArray(65536)
                            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
                        } ?: throw IllegalStateException()
                        val hash = digest.digest().joinToString("") { "%02x".format(it) }
                        val image = InputImage.fromFilePath(activity, uri)
                        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                        recognizer.process(image).addOnSuccessListener { text ->
                            result.success(mapOf("text" to text.text, "hash" to hash, "languages" to listOf("en"), "confidence" to null,
                                "blocks" to text.textBlocks.flatMap { b -> b.lines }.map { line ->
                                    val r = line.boundingBox
                                    val w = (if (image.rotationDegrees % 180 == 0) image.width else image.height).coerceAtLeast(1).toDouble()
                                    val h = (if (image.rotationDegrees % 180 == 0) image.height else image.width).coerceAtLeast(1).toDouble()
                                    mapOf("text" to line.text, "box" to listOf((r?.left ?: 0) / w, (r?.top ?: 0) / h, (r?.width() ?: 0) / w, (r?.height() ?: 0) / h), "confidence" to line.confidence)
                                }))
                            recognizer.close()
                        }.addOnFailureListener { result.error("ocr", "On-device recognition failed", null); recognizer.close() }
                    } catch (_: Exception) { main.post { result.error("media", "Image unavailable or access revoked", null) } }
                }
            }
            else -> result.notImplemented()
        }
    }
    private fun authorizedUri(call: MethodCall): Uri {
        val uri = Uri.parse(call.argument<String>("id") ?: throw IllegalArgumentException())
        require(uri.scheme == "content")
        return uri // ContentResolver enforces the current OS grant on each read.
    }
    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try { val value = block(); main.post { result.success(value) } }
            catch (_: Exception) { main.post { result.error("media", "Image unavailable or access revoked", null) } }
        }
    }
    private fun updateObserver() {
        if (observing) { resolver.unregisterContentObserver(observer); observing = false }
        if (preferences.getBoolean("automatic", false) && permission() != "denied") {
            resolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, observer); observing = true
        }
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }
    fun close() { if (observing) resolver.unregisterContentObserver(observer); executor.shutdown(); channel.setMethodCallHandler(null) }
}
