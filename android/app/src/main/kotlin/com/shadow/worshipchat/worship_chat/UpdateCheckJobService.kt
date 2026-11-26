package com.shadow.worshipchat

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.pm.PackageInfoCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Periodic Android JobScheduler worker that checks GitHub Releases for a newer
 * Worship Chat APK and posts a system notification if one is available.
 *
 * Uses the same FlutterSharedPreferences deduplication keys as Dart
 * [AppUpdateService] so a release only triggers one push notification per build.
 */
class UpdateCheckJobService : JobService() {
    @Volatile
    private var isCancelled = false

    companion object {
        private const val TAG = "UpdateCheckJobService"
        const val JOB_ID = 900101
        const val NOTIFICATION_ID = 900100
        const val CHANNEL_ID = "app_updates_channel"
        const val CHANNEL_NAME = "App Updates"
        const val CHANNEL_DESC =
            "Notifications when a new Worship Chat APK update is available."
        const val GITHUB_RELEASE_URL =
            "https://api.github.com/repos/spideynk25/worship_chat/releases/latest"
        const val EXTRA_LAUNCH_APP_UPDATE = "launch_app_update"

        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val KEY_PHONE_ENABLED = "flutter.phone_chat_enabled"
        private const val KEY_NOTIFIED_CODE = "flutter.notified_update_version_code"
        private const val KEY_NOTIFIED_NAME = "flutter.notified_update_version_name"
        private const val SIX_HOURS_MS = 6L * 60L * 60L * 1000L

        fun schedule(context: Context) {
            try {
                val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE)
                    as? JobScheduler ?: return
                if (scheduler.allPendingJobs.any { it.id == JOB_ID }) {
                    return
                }
                val builder = JobInfo.Builder(
                    JOB_ID,
                    ComponentName(context, UpdateCheckJobService::class.java),
                )
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                    .setPeriodic(SIX_HOURS_MS)
                    .setPersisted(true)

                scheduler.schedule(builder.build())
            } catch (e: Exception) {
                Log.w(TAG, "Unable to schedule periodic update job: ${e.message}")
            }
        }
    }

    override fun onStartJob(params: JobParameters?): Boolean {
        isCancelled = false
        Thread {
            try {
                if (!isCancelled) {
                    checkForUpdateAndNotify()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Background update check failed: ${e.message}")
            } finally {
                jobFinished(params, false)
            }
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean {
        isCancelled = true
        return true
    }

    private fun checkForUpdateAndNotify() {
        val prefs = applicationContext.getSharedPreferences(
            FLUTTER_PREFS,
            Context.MODE_PRIVATE,
        )
        if (!prefs.getBoolean(KEY_PHONE_ENABLED, false)) {
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) return
        }

        val releaseJson = fetchLatestReleaseJson() ?: return
        if (releaseJson.optBoolean("draft", false) ||
            releaseJson.optBoolean("prerelease", false)
        ) {
            return
        }

        val assets = releaseJson.optJSONArray("assets") ?: return
        var hasApkAsset = false
        for (i in 0 until assets.length()) {
            val item = assets.optJSONObject(i) ?: continue
            val name = item.optString("name", "").trim().lowercase()
            val url = item.optString("browser_download_url", "").trim()
            if (name.endsWith(".apk") &&
                (url.startsWith("http://") || url.startsWith("https://"))
            ) {
                hasApkAsset = true
                break
            }
        }
        if (!hasApkAsset) return

        val rawTag = releaseJson.optString("tag_name", "").ifBlank {
            releaseJson.optString("name", "")
        }.trim()
        if (rawTag.isEmpty()) return

        val (remoteName, remoteCode) = parseTagVersion(rawTag)
        if (remoteCode <= 0 && remoteName.isEmpty()) return

        val pInfo = applicationContext.packageManager.getPackageInfo(
            applicationContext.packageName,
            0,
        )
        val installedCode = PackageInfoCompat.getLongVersionCode(pInfo).toInt()
        val installedName = (pInfo.versionName ?: "1.0.0").trim()

        if (!isNewerThan(remoteCode, remoteName, installedCode, installedName)) {
            return
        }

        val lastNotifiedCode = readPrefInt(prefs, KEY_NOTIFIED_CODE)
        val lastNotifiedName = prefs.getString(KEY_NOTIFIED_NAME, "") ?: ""
        if (lastNotifiedCode > 0 &&
            !isNewerThan(remoteCode, remoteName, lastNotifiedCode, lastNotifiedName)
        ) {
            return
        }

        val rawBody = releaseJson.optString("body", "")
        val forceUpdate = Regex("""(\[FORCE\]|forceUpdate\s*:\s*true)""", RegexOption.IGNORE_CASE)
            .containsMatchIn(rawBody)
        val cleanedNotes = rawBody
            .replace(Regex("""sha256\s*:\s*[a-fA-F0-9]{64}""", RegexOption.IGNORE_CASE), "")
            .replace(Regex("""forceUpdate\s*:\s*(true|false)""", RegexOption.IGNORE_CASE), "")
            .replace(Regex("""\[FORCE\]""", RegexOption.IGNORE_CASE), "")
            .lines()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .take(2)
            .joinToString(" • ")

        val displayVersion = if (remoteName.isNotEmpty()) remoteName else "b$remoteCode"
        postUpdateNotification(
            versionName = displayVersion,
            versionCode = remoteCode,
            summary = cleanedNotes,
            forceUpdate = forceUpdate,
        )

        prefs.edit()
            .putLong(KEY_NOTIFIED_CODE, remoteCode.toLong())
            .putString(KEY_NOTIFIED_NAME, displayVersion)
            .apply()
    }

    private fun fetchLatestReleaseJson(): JSONObject? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(GITHUB_RELEASE_URL).openConnection() as HttpURLConnection).apply {
                connectTimeout = 10000
                readTimeout = 10000
                requestMethod = "GET"
                setRequestProperty("Accept", "application/vnd.github+json")
                setRequestProperty("User-Agent", "WorshipChat-Android")
            }
            if (conn.responseCode != 200) return null
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            JSONObject(body)
        } catch (_: Exception) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun postUpdateNotification(
        versionName: String,
        versionCode: Int,
        summary: String,
        forceUpdate: Boolean,
    ) {
        val mgr = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = CHANNEL_DESC
                enableVibration(true)
                enableLights(true)
            }
            mgr.createNotificationChannel(channel)
        }

        val title = if (forceUpdate) {
            "⚡ Required Update: Worship Chat v$versionName"
        } else {
            "✨ Worship Chat v$versionName Available"
        }
        val body = if (summary.isNotEmpty()) {
            if (summary.length > 140) summary.substring(0, 137) + "..." else summary
        } else {
            "Tap to download and install Build $versionCode."
        }

        val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_LAUNCH_APP_UPDATE, true)
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            NOTIFICATION_ID,
            launchIntent,
            pendingFlags,
        )

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setColor(0xFFD4AF37.toInt())
            .setContentIntent(pendingIntent)
            .build()

        mgr.notify("app_update", NOTIFICATION_ID, notification)
    }

    private fun readPrefInt(prefs: SharedPreferences, key: String): Int {
        val raw = prefs.all[key]
        return when (raw) {
            is Number -> raw.toInt()
            is String -> raw.toIntOrNull() ?: 0
            else -> 0
        }
    }

    private fun parseTagVersion(rawTag: String): Pair<String, Int> {
        val cleaned = rawTag.replaceFirst(Regex("^v", RegexOption.IGNORE_CASE), "").trim()
        val match = Regex("""^(\d+(?:\.\d+)*)(?:(?:\+|-b(?:uild)?\.?)(\d+))?""", RegexOption.IGNORE_CASE)
            .find(cleaned)
        return if (match != null) {
            val vName = match.groupValues.getOrNull(1) ?: ""
            val vCode = match.groupValues.getOrNull(2)?.toIntOrNull() ?: 0
            vName to vCode
        } else {
            cleaned to 0
        }
    }

    private fun isNewerThan(
        remoteCode: Int,
        remoteName: String,
        currentCode: Int,
        currentName: String,
    ): Boolean {
        if (remoteCode > currentCode) return true
        if (remoteCode in 1 until currentCode) return false
        if (remoteName.isNotEmpty()) {
            return compareSemver(remoteName, currentName) > 0
        }
        return false
    }

    private fun compareSemver(a: String, b: String): Int {
        fun parts(v: String): List<Int> {
            val clean = v.replaceFirst(Regex("^v", RegexOption.IGNORE_CASE), "")
                .substringBefore('+')
                .substringBefore('-')
            return clean.split('.').map { it.trim().toIntOrNull() ?: 0 }
        }
        val pa = parts(a)
        val pb = parts(b)
        val len = maxOf(pa.size, pb.size)
        for (i in 0 until len) {
            val va = pa.getOrElse(i) { 0 }
            val vb = pb.getOrElse(i) { 0 }
            if (va != vb) return va.compareTo(vb)
        }
        return 0
    }
}
