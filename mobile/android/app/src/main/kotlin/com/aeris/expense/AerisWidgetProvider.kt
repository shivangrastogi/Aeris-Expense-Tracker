package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Home-screen widget showing "budget left" + a progress bar, pushed from the
/// Flutter app. Tapping it opens the app.
class AerisWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.aeris_widget).apply {
                setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("title", "Budget left") ?: "Budget left"
                )
                setTextViewText(
                    R.id.widget_amount,
                    widgetData.getString("amount", "—") ?: "—"
                )
                setTextViewText(
                    R.id.widget_sub,
                    widgetData.getString("sub", "") ?: ""
                )
                setProgressBar(R.id.widget_progress, 100, widgetData.getInt("pct", 0), false)

                // Tap anywhere → open the app.
                val pending = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_root, pending)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
