package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 2x2 "My Village" widget. Tap opens the village builder.
class AerisVillageWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_village_widget).apply {
                setTextViewText(
                    R.id.widget_village_lvl,
                    "🏰 " + (widgetData.getString("village_lvl", "Lv 1") ?: "Lv 1")
                )
                setTextViewText(
                    R.id.widget_village_aura,
                    "⚡ " + (widgetData.getString("village_aura", "0") ?: "0")
                )
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("aeriswidget://village")
                    )
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
