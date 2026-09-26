package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 2x2 "Spent this month" widget.
class AerisSpentWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_spent_widget).apply {
                setTextViewText(
                    R.id.widget_spent_amount,
                    widgetData.getString("spent_text", "—") ?: "—"
                )
                setTextViewText(
                    R.id.widget_spent_sub,
                    widgetData.getString("spent_sub", "") ?: ""
                )
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
