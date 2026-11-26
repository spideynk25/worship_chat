package com.shadow.worshipchat

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.media.ExifInterface
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class WorshipPhotoWidgetProvider : AppWidgetProvider() {

    companion object {
        const val PREFS_NAME = "worship_photo_widget"
        const val KEY_PHOTOS_JSON = "photos_json"
        const val KEY_CURRENT_INDEX = "current_index"
        const val KEY_SHOW_TITLE = "show_title"
        const val KEY_INTERVAL_MINUTES = "interval_minutes"
        const val KEY_LAST_ROTATED_MS = "last_rotated_ms"
        const val KEY_SOURCE_LABEL = "source_label"

        const val ACTION_NEXT_PHOTO = "com.shadow.worshipchat.WIDGET_NEXT_PHOTO"

        private const val MAX_WIDGET_BITMAP_EDGE = 400
        private const val MAX_BINDER_BITMAP_BYTES = 750_000

        fun saveConfig(
            context: Context,
            photos: List<Map<String, Any?>>,
            currentIndex: Int,
            showTitle: Boolean,
            intervalMinutes: Int,
            sourceLabel: String
        ) {
            val jsonArray = JSONArray()
            for (item in photos) {
                val path = item["path"]?.toString()?.trim().orEmpty()
                if (path.isEmpty()) continue
                val obj = JSONObject().apply {
                    put("path", path)
                    put("title", item["title"]?.toString() ?: "")
                    put("subtitle", item["subtitle"]?.toString() ?: "")
                }
                jsonArray.put(obj)
            }

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val safeIndex = if (jsonArray.length() == 0) 0 else ((currentIndex % jsonArray.length()) + jsonArray.length()) % jsonArray.length()
            prefs.edit()
                .putString(KEY_PHOTOS_JSON, jsonArray.toString())
                .putInt(KEY_CURRENT_INDEX, safeIndex)
                .putBoolean(KEY_SHOW_TITLE, showTitle)
                .putInt(KEY_INTERVAL_MINUTES, intervalMinutes)
                .putString(KEY_SOURCE_LABEL, sourceLabel)
                .putLong(KEY_LAST_ROTATED_MS, System.currentTimeMillis())
                .apply()

            updateAllWidgets(context, allowIntervalAdvance = false)
        }

        fun advanceAndRedraw(context: Context): Int {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val entries = loadValidPhotos(prefs)
            if (entries.isEmpty()) {
                updateAllWidgets(context, allowIntervalAdvance = false)
                return 0
            }
            val prev = prefs.getInt(KEY_CURRENT_INDEX, 0)
            val next = (prev + 1) % entries.size
            prefs.edit()
                .putInt(KEY_CURRENT_INDEX, next)
                .putLong(KEY_LAST_ROTATED_MS, System.currentTimeMillis())
                .apply()
            updateAllWidgets(context, allowIntervalAdvance = false)
            return next
        }

        fun getInstalledCount(context: Context): Int {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, WorshipPhotoWidgetProvider::class.java))
            return ids.size
        }

        fun getCurrentIndex(context: Context): Int {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return prefs.getInt(KEY_CURRENT_INDEX, 0)
        }

        fun updateAllWidgets(context: Context, allowIntervalAdvance: Boolean = false) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, WorshipPhotoWidgetProvider::class.java))
            if (ids.isEmpty()) return

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val entries = loadValidPhotos(prefs)

            if (allowIntervalAdvance && entries.size > 1) {
                val intervalMinutes = prefs.getInt(KEY_INTERVAL_MINUTES, 60)
                if (intervalMinutes > 0) {
                    val lastRotated = prefs.getLong(KEY_LAST_ROTATED_MS, 0L)
                    val now = System.currentTimeMillis()
                    if (lastRotated > 0L && (now - lastRotated) >= intervalMinutes * 60_000L) {
                        val next = (prefs.getInt(KEY_CURRENT_INDEX, 0) + 1) % entries.size
                        prefs.edit()
                            .putInt(KEY_CURRENT_INDEX, next)
                            .putLong(KEY_LAST_ROTATED_MS, now)
                            .apply()
                    }
                }
            }

            for (appWidgetId in ids) {
                updateSingleWidget(context, mgr, appWidgetId, prefs, entries)
            }
        }

        private data class WidgetPhotoEntry(
            val path: String,
            val title: String,
            val subtitle: String
        )

        private fun loadValidPhotos(prefs: android.content.SharedPreferences): List<WidgetPhotoEntry> {
            val raw = prefs.getString(KEY_PHOTOS_JSON, null) ?: return emptyList()
            val list = mutableListOf<WidgetPhotoEntry>()
            try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    val path = obj.optString("path").trim()
                    if (path.isNotEmpty() && File(path).exists()) {
                        list.add(
                            WidgetPhotoEntry(
                                path = path,
                                title = obj.optString("title"),
                                subtitle = obj.optString("subtitle")
                            )
                        )
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("WorshipPhotoWidget", "Failed to parse widget photos: $e")
            }
            return list
        }

        private fun updateSingleWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            prefs: android.content.SharedPreferences,
            entries: List<WidgetPhotoEntry>
        ) {
            val views = RemoteViews(context.packageName, R.layout.worship_photo_widget)

            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                } ?: Intent(context, MainActivity::class.java)

            val launchPending = PendingIntent.getActivity(
                context,
                appWidgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, launchPending)

            val nextIntent = Intent(context, WorshipPhotoWidgetProvider::class.java).apply {
                action = ACTION_NEXT_PHOTO
            }
            val nextPending = PendingIntent.getBroadcast(
                context,
                10_000 + appWidgetId,
                nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_next_btn, nextPending)

            if (entries.isEmpty()) {
                views.setViewVisibility(R.id.widget_empty_container, View.VISIBLE)
                views.setViewVisibility(R.id.widget_photo, View.GONE)
                views.setViewVisibility(R.id.widget_footer, View.GONE)
                appWidgetManager.updateAppWidget(appWidgetId, views)
                return
            }

            val rawIndex = prefs.getInt(KEY_CURRENT_INDEX, 0)
            val safeIndex = ((rawIndex % entries.size) + entries.size) % entries.size
            if (safeIndex != rawIndex) {
                prefs.edit().putInt(KEY_CURRENT_INDEX, safeIndex).apply()
            }

            val entry = entries[safeIndex]
            val cornerPx = 18f * context.resources.displayMetrics.density
            val roundedBitmap = decodeRoundedBitmap(entry.path, cornerPx)

            if (roundedBitmap == null) {
                views.setViewVisibility(R.id.widget_empty_container, View.VISIBLE)
                views.setViewVisibility(R.id.widget_photo, View.GONE)
                views.setViewVisibility(R.id.widget_footer, View.GONE)
                appWidgetManager.updateAppWidget(appWidgetId, views)
                return
            }

            views.setViewVisibility(R.id.widget_empty_container, View.GONE)
            views.setViewVisibility(R.id.widget_photo, View.VISIBLE)
            views.setImageViewBitmap(R.id.widget_photo, roundedBitmap)

            val showTitle = prefs.getBoolean(KEY_SHOW_TITLE, true)
            val sourceLabel = prefs.getString(KEY_SOURCE_LABEL, "").orEmpty().trim()
            val showNextBtn = entries.size > 1
            views.setViewVisibility(
                R.id.widget_next_btn,
                if (showNextBtn) View.VISIBLE else View.GONE
            )

            if (!showTitle && !showNextBtn) {
                views.setViewVisibility(R.id.widget_footer, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_footer, View.VISIBLE)
                val primaryTitle = when {
                    !showTitle -> ""
                    entry.title.isNotBlank() -> entry.title
                    sourceLabel.isNotBlank() -> sourceLabel
                    else -> "Worship Chat"
                }
                val counter = if (entries.size > 1) "${safeIndex + 1} / ${entries.size}" else ""
                val secondaryText = if (!showTitle) {
                    ""
                } else if (entry.subtitle.isNotBlank() && counter.isNotBlank()) {
                    "${entry.subtitle} • $counter"
                } else if (counter.isNotBlank()) {
                    counter
                } else {
                    entry.subtitle
                }

                views.setTextViewText(R.id.widget_title, primaryTitle)
                views.setViewVisibility(
                    R.id.widget_title,
                    if (primaryTitle.isNotEmpty()) View.VISIBLE else View.GONE
                )
                views.setTextViewText(R.id.widget_subtitle, secondaryText)
                views.setViewVisibility(
                    R.id.widget_subtitle,
                    if (secondaryText.isNotEmpty()) View.VISIBLE else View.GONE
                )
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun decodeRoundedBitmap(path: String, radiusPx: Float): Bitmap? {
            return try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

                var sampleSize = 1
                while (maxOf(bounds.outWidth / sampleSize, bounds.outHeight / sampleSize) > MAX_WIDGET_BITMAP_EDGE * 2) {
                    sampleSize *= 2
                }

                val opts = BitmapFactory.Options().apply {
                    inSampleSize = sampleSize
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                var decoded = BitmapFactory.decodeFile(path, opts) ?: return null

                // Apply EXIF rotation if present
                val rotationDegrees = readExifRotation(path)
                if (rotationDegrees != 0f) {
                    val matrix = Matrix().apply { postRotate(rotationDegrees) }
                    val rotated = Bitmap.createBitmap(
                        decoded,
                        0,
                        0,
                        decoded.width,
                        decoded.height,
                        matrix,
                        true
                    )
                    if (rotated != decoded) {
                        decoded.recycle()
                        decoded = rotated
                    }
                }

                // Scale strictly within MAX_WIDGET_BITMAP_EDGE & binder limit
                val maxSide = maxOf(decoded.width, decoded.height)
                if (maxSide > MAX_WIDGET_BITMAP_EDGE) {
                    val ratio = MAX_WIDGET_BITMAP_EDGE.toFloat() / maxSide.toFloat()
                    val w = maxOf(1, (decoded.width * ratio).toInt())
                    val h = maxOf(1, (decoded.height * ratio).toInt())
                    val scaled = Bitmap.createScaledBitmap(decoded, w, h, true)
                    if (scaled != decoded) {
                        decoded.recycle()
                        decoded = scaled
                    }
                }

                while (decoded.byteCount > MAX_BINDER_BITMAP_BYTES && minOf(decoded.width, decoded.height) > 64) {
                    val w = maxOf(1, (decoded.width * 0.8f).toInt())
                    val h = maxOf(1, (decoded.height * 0.8f).toInt())
                    val shrunk = Bitmap.createScaledBitmap(decoded, w, h, true)
                    decoded.recycle()
                    decoded = shrunk
                }

                val out = Bitmap.createBitmap(decoded.width, decoded.height, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(out)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG)
                val rect = RectF(0f, 0f, decoded.width.toFloat(), decoded.height.toFloat())
                canvas.drawRoundRect(rect, radiusPx, radiusPx, paint)
                paint.xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.SRC_IN)
                canvas.drawBitmap(decoded, 0f, 0f, paint)
                decoded.recycle()
                out
            } catch (e: Exception) {
                android.util.Log.e("WorshipPhotoWidget", "Bitmap decode failed: $e")
                null
            }
        }

        private fun readExifRotation(path: String): Float {
            return try {
                val exif = ExifInterface(path)
                when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
            } catch (_: Exception) {
                0f
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateAllWidgets(context, allowIntervalAdvance = true)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_NEXT_PHOTO) {
            advanceAndRedraw(context)
        }
    }
}
