package com.abrahanq.rapidobcv

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

class RapidobcvWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val ACTION_DAILY_REFRESH = "com.abrahanq.rapidobcv.action.DAILY_WIDGET_REFRESH"
        private const val REFRESH_REQUEST_CODE = 4201
        private const val WIDGET_CACHE_NAME = "rapidobcv_widget_cache"
        private const val PRICES_ENDPOINT = "https://abrahanq.github.io/bcv-price/prices.json"
    }

    private data class WidgetRates(
        val usd: String,
        val eur: String,
        val usdt: String,
        val lastUpdate: String,
        val timestamp: Long,
    )

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleDailyRefresh(context)
        refreshFromNetworkAsync(context)
    }

    override fun onDisabled(context: Context) {
        cancelDailyRefresh(context)
        super.onDisabled(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        when (intent.action) {
            ACTION_DAILY_REFRESH -> {
                scheduleDailyRefresh(context)
                refreshFromNetworkAsync(context)
            }
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                scheduleDailyRefresh(context)
                refreshFromNetworkAsync(context)
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        scheduleDailyRefresh(context)

        val cache = context.getSharedPreferences(WIDGET_CACHE_NAME, Context.MODE_PRIVATE)
        val lastUpdate = widgetData.getString("last_update", null)
            ?: cache.getString("last_update", "Sin datos")
            ?: "Sin datos"
        val usdValue = widgetData.getString("usd_value", null)
            ?: cache.getString("usd_value", "-")
            ?: "-"
        val eurValue = widgetData.getString("eur_value", null)
            ?: cache.getString("eur_value", "-")
            ?: "-"
        val usdtValue = widgetData.getString("usdt_value", null)
            ?: cache.getString("usdt_value", "-")
            ?: "-"

        updateWidgets(context, appWidgetManager, appWidgetIds, lastUpdate, usdValue, eurValue, usdtValue)
        refreshFromNetworkAsync(context)
    }

    private fun updateWidgets(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        lastUpdate: String,
        usdValue: String,
        eurValue: String,
        usdtValue: String,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.rapidobcv_widget_layout).apply {
                setTextViewText(
                    R.id.widget_last_update,
                    lastUpdate,
                )
                setTextViewText(
                    R.id.widget_usd_value,
                    usdValue,
                )
                setTextViewText(
                    R.id.widget_eur_value,
                    eurValue,
                )
                setTextViewText(
                    R.id.widget_usdt_value,
                    usdtValue,
                )

                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    val pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, flags)
                    setOnClickPendingIntent(R.id.widget_root, pendingIntent)
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun refreshFromNetworkAsync(context: Context) {
        Thread {
            runCatching {
                val rates = fetchLatestRates() ?: return@runCatching
                persistRates(context, rates)
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val ids = appWidgetManager.getAppWidgetIds(
                    ComponentName(context, RapidobcvWidgetProvider::class.java),
                )
                if (ids.isNotEmpty()) {
                    updateWidgets(
                        context,
                        appWidgetManager,
                        ids,
                        rates.lastUpdate,
                        rates.usd,
                        rates.eur,
                        rates.usdt,
                    )
                }
            }
        }.start()
    }

    private fun fetchLatestRates(): WidgetRates? {
        val connection = URL(PRICES_ENDPOINT).openConnection() as HttpURLConnection
        connection.connectTimeout = 10000
        connection.readTimeout = 10000
        connection.requestMethod = "GET"
        connection.setRequestProperty("Accept", "application/json")

        return try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                null
            } else {
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                val root = JSONObject(body)
                val records = mutableListOf<WidgetRates>()

                val precios = root.optJSONArray("precios")
                if (precios != null && precios.length() > 0) {
                    for (i in 0 until precios.length()) {
                        val item = precios.optJSONObject(i) ?: continue
                        parseRateRecord(item)?.let(records::add)
                    }
                } else {
                    parseRateRecord(root)?.let(records::add)
                }

                records.maxByOrNull { it.timestamp }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun parseRateRecord(record: JSONObject): WidgetRates? {
        val usd = record.optDouble("usd", Double.NaN)
        val eur = record.optDouble("eur", Double.NaN)
        if (usd.isNaN() || eur.isNaN()) {
            return null
        }

        val usdtRaw = record.optDouble("usdt", Double.NaN)
        val usdt = if (usdtRaw.isNaN()) usd else usdtRaw
        val dateText = record.optString("date", record.optString("fecha", ""))
        val timestamp = parseIsoDateToTimestamp(dateText)
        val formattedDate = formatShortDate(timestamp)

        return WidgetRates(
            usd = String.format(Locale.US, "%.2f", usd),
            eur = String.format(Locale.US, "%.2f", eur),
            usdt = String.format(Locale.US, "%.2f", usdt),
            lastUpdate = formattedDate,
            timestamp = timestamp,
        )
    }

    private fun parseIsoDateToTimestamp(dateText: String): Long {
        if (dateText.isBlank()) {
            return System.currentTimeMillis()
        }

        val year = dateText.take(4).toIntOrNull() ?: return System.currentTimeMillis()
        val month = dateText.drop(5).take(2).toIntOrNull() ?: return System.currentTimeMillis()
        val day = dateText.drop(8).take(2).toIntOrNull() ?: return System.currentTimeMillis()

        val hour = if (dateText.length >= 13) dateText.drop(11).take(2).toIntOrNull() ?: 0 else 0
        val minute = if (dateText.length >= 16) dateText.drop(14).take(2).toIntOrNull() ?: 0 else 0
        val second = if (dateText.length >= 19) dateText.drop(17).take(2).toIntOrNull() ?: 0 else 0

        val isUtc = dateText.endsWith("Z") || dateText.contains("+00:00")
        val zone = if (isUtc) TimeZone.getTimeZone("UTC") else TimeZone.getDefault()

        return Calendar.getInstance(zone).run {
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month - 1)
            set(Calendar.DAY_OF_MONTH, day)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, second)
            set(Calendar.MILLISECOND, 0)
            timeInMillis
        }
    }

    private fun formatShortDate(timestamp: Long): String {
        val calendar = Calendar.getInstance().apply { timeInMillis = timestamp }
        val day = calendar.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
        val month = (calendar.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
        val hour = calendar.get(Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
        val minute = calendar.get(Calendar.MINUTE).toString().padStart(2, '0')
        return "$day/$month $hour:$minute"
    }

    private fun persistRates(context: Context, rates: WidgetRates) {
        val cache = context.getSharedPreferences(WIDGET_CACHE_NAME, Context.MODE_PRIVATE)
        cache.edit()
            .putString("last_update", rates.lastUpdate)
            .putString("usd_value", rates.usd)
            .putString("eur_value", rates.eur)
            .putString("usdt_value", rates.usdt)
            .apply()
    }

    private fun scheduleDailyRefresh(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val refreshIntent = Intent(context, RapidobcvWidgetProvider::class.java).apply {
            action = ACTION_DAILY_REFRESH
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REFRESH_REQUEST_CODE,
            refreshIntent,
            flags,
        )

        val nextRun = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 1)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (before(Calendar.getInstance()) || timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                nextRun.timeInMillis,
                pendingIntent,
            )
        } else {
            alarmManager.set(
                AlarmManager.RTC_WAKEUP,
                nextRun.timeInMillis,
                pendingIntent,
            )
        }
    }

    private fun cancelDailyRefresh(context: Context) {
        val refreshIntent = Intent(context, RapidobcvWidgetProvider::class.java).apply {
            action = ACTION_DAILY_REFRESH
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REFRESH_REQUEST_CODE,
            refreshIntent,
            flags,
        )

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }
}
