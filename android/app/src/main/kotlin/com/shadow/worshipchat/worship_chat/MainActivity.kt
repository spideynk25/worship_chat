package com.shadow.worshipchat

import android.accounts.AccountManager
import android.content.Context
import android.telephony.TelephonyManager
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
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
}
