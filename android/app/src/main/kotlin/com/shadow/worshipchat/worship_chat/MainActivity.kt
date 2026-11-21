package com.shadow.worshipchat

import android.accounts.AccountManager
import android.app.NotificationManager
import android.content.Context
import android.content.res.Resources
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager
import android.telephony.TelephonyManager
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// ✅ Missing imports
import android.net.Uri
import android.content.ContentResolver
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "my.app/accounts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "worship_chat/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTablet" -> result.success(isTabletDevice())
                    "acquireWakeLock" -> {
                        acquireWakeLock()
                        result.success(true)
                    }
                    "releaseWakeLock" -> {
                        releaseWakeLock()
                        result.success(true)
                    }
                    "disableNotifications" -> {
                        if (isTabletDevice()) {
                            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            manager.cancelAll()
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "openGoogleLens" -> {
                        val path = call.argument<String>("path")
                        val url = call.argument<String>("url")
                        val opened = openGoogleLens(path, url)
                        result.success(opened)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "getAllAccounts" -> {
                        try {
                            val am = getSystemService(Context.ACCOUNT_SERVICE) as AccountManager
                            val accounts = am.accounts
                            val accountList = accounts.map { "${it.name} (${it.type})" }
                            result.success(accountList)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    "getDevicePhoneNumber" -> {
                        try {
                            val telephonyManager =
                                getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                            if (ActivityCompat.checkSelfPermission(
                                    this,
                                    Manifest.permission.READ_PHONE_NUMBERS
                                ) == PackageManager.PERMISSION_GRANTED ||
                                ActivityCompat.checkSelfPermission(
                                    this,
                                    Manifest.permission.READ_PHONE_STATE
                                ) == PackageManager.PERMISSION_GRANTED
                            ) {
                                val phoneNumber = telephonyManager.line1Number
                                result.success(phoneNumber)
                            } else {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    "readContentUri" -> {
                        val uriString = call.argument<String>("uri")
                        val data = readContentUri(uriString)
                        if (data != null) {
                            result.success(data)
                        } else {
                            result.error("READ_ERROR", "Failed to read content URI", null)
                        }
                    }

                     "getFilePath" -> {
                        val uriString = call.argument<String>("uri")
                        val path = copyContentUriToFile(uriString)
                        if (path != null) {
                            result.success(path)
                        } else {
                            result.error("COPY_ERROR", "Failed to copy content URI to file", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    private fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "WorshipChat:BackgroundTransfer")
                wakeLock?.setReferenceCounted(false)
            }
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(15 * 60 * 1000L) // 15 mins safeguard
                android.util.Log.d("MainActivity", "WakeLock acquired for background task")
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error acquiring WakeLock: ")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                android.util.Log.d("MainActivity", "WakeLock released")
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error releasing WakeLock: ")
        }
    }

    private fun isTabletDevice(): Boolean {
        // Use the full display, so split-screen and window resizing cannot enable chat.
        val shortestSideDp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val bounds = windowManager.maximumWindowMetrics.bounds
            minOf(bounds.width(), bounds.height()) / resources.displayMetrics.density
        } else {
            val metrics = Resources.getSystem().displayMetrics
            minOf(metrics.widthPixels, metrics.heightPixels) / metrics.density
        }
        return shortestSideDp >= 600f
    }

     private fun readContentUri(uriString: String?): ByteArray? {
        if (uriString == null) return null
        
        return try {
            val uri = Uri.parse(uriString)
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            
            val buffer = ByteArrayOutputStream()
            val data = ByteArray(16384) // 16KB buffer
            var bytesRead: Int
            
            while (inputStream.read(data, 0, data.size).also { bytesRead = it } != -1) {
                buffer.write(data, 0, bytesRead)
            }
            
            inputStream.close()
            buffer.flush()
            
            val byteArray = buffer.toByteArray()
            android.util.Log.d("MainActivity", "Read ${byteArray.size} bytes from URI: $uriString")
            
            byteArray
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error reading content URI: $e")
            e.printStackTrace()
            null
        }
    }

     private fun copyContentUriToFile(uriString: String?): String? {
        if (uriString == null) return null
        
        return try {
            val uri = Uri.parse(uriString)
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            
            // Get file extension from MIME type or URI
            val extension = getFileExtension(uri)
            
            // Create temporary file
            val tempFile = File(
                cacheDir,
                "gif_${System.currentTimeMillis()}.$extension"
            )
            
            // Copy data to file
            FileOutputStream(tempFile).use { output ->
                val buffer = ByteArray(8192)
                var bytesRead: Int
                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    output.write(buffer, 0, bytesRead)
                }
            }
            
            inputStream.close()
            
            android.util.Log.d("MainActivity", "Copied to file: ${tempFile.absolutePath}")
            tempFile.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error copying content URI: $e")
            e.printStackTrace()
            null
        }
    }

    /**
     * Get file extension from URI
     */
    private fun getFileExtension(uri: Uri): String {
        // Try to get from MIME type
        val mimeType = contentResolver.getType(uri)
        if (mimeType != null) {
            when {
                mimeType.contains("gif") -> return "gif"
                mimeType.contains("png") -> return "png"
                mimeType.contains("jpeg") || mimeType.contains("jpg") -> return "jpg"
            }
        }
        
        // Fallback to URI path
        val path = uri.path
        if (path != null) {
            val lastDot = path.lastIndexOf('.')
            if (lastDot > 0) {
                return path.substring(lastDot + 1)
            }
        }
        
        // Default to gif
        return "gif"
    }

    private fun openGoogleLens(filePath: String?, imageUrl: String?): Boolean {
        // 1. If local file exists, try native Android Intents
        if (!filePath.isNullOrBlank()) {
            try {
                val cleanPath = if (filePath.startsWith("file://")) filePath.removePrefix("file://") else filePath
                val file = File(cleanPath)
                if (file.exists() && file.isFile) {
                    val uri: Uri = FileProvider.getUriForFile(
                        this,
                        "${packageName}.fileprovider",
                        file
                    )

                    // Priority 1: Google Lens dedicated app
                    val lensIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "image/*"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        setPackage("com.google.ar.lens")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    if (lensIntent.resolveActivity(packageManager) != null) {
                        startActivity(lensIntent)
                        return true
                    }

                    // Priority 2: Google QuickSearchBox (Google app with built-in Lens)
                    val googleIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "image/*"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        setPackage("com.google.android.googlequicksearchbox")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    if (googleIntent.resolveActivity(packageManager) != null) {
                        startActivity(googleIntent)
                        return true
                    }

                    // If no remote URL is present, launch standard chooser with ACTION_SEND
                    if (imageUrl.isNullOrBlank() || (!imageUrl.startsWith("http://") && !imageUrl.startsWith("https://"))) {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "image/*"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        val chooser = Intent.createChooser(shareIntent, "Search with Google Lens")
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        return true
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Failed to launch native Google Lens: $e")
            }
        }

        // 2. If remote web URL is available, open Google Lens web URL
        if (!imageUrl.isNullOrBlank() && (imageUrl.startsWith("http://") || imageUrl.startsWith("https://"))) {
            try {
                val lensWebUrl = "https://lens.google.com/uploadbyurl?url=" + Uri.encode(imageUrl)
                val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(lensWebUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(browserIntent)
                return true
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Failed to open Lens web URL: $e")
            }
        }

        return false
    }
}
