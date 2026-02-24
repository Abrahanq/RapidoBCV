package com.abrahanq.rapidobcv

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class RapidobcvWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.rapidobcv_widget_layout).apply {
                setTextViewText(
                    R.id.widget_last_update,
                    widgetData.getString("last_update", "Sin datos") ?: "Sin datos",
                )
                setTextViewText(
                    R.id.widget_usd_value,
                    widgetData.getString("usd_value", "-") ?: "-",
                )
                setTextViewText(
                    R.id.widget_eur_value,
                    widgetData.getString("eur_value", "-") ?: "-",
                )
                setTextViewText(
                    R.id.widget_usdt_value,
                    widgetData.getString("usdt_value", "-") ?: "-",
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
}
