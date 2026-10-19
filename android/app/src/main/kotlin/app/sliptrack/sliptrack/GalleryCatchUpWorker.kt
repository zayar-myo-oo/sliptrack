package app.sliptrack.sliptrack

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.work.Worker
import androidx.work.WorkerParameters

// Deferred discovery signal only. Financial OCR/import runs in the foreground
// where the encrypted Flutter repository and consent UI are available.
class GalleryCatchUpWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences("sliptrack.media", 0)
        if (!prefs.getBoolean("automatic", false)) return Result.success()
        val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        if (ContextCompat.checkSelfPermission(applicationContext, permission) != PackageManager.PERMISSION_GRANTED) return Result.success()
        return try {
            applicationContext.contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Images.Media._ID), null, null, "${MediaStore.Images.Media._ID} DESC")?.use {
                if (it.moveToFirst()) prefs.edit().putBoolean("catchupPending", true).apply()
            }
            Result.success()
        } catch (_: SecurityException) { Result.success() } catch (_: Exception) { Result.retry() }
    }
}
