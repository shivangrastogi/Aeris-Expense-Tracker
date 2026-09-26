package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 2x1 compact streak widget.
class AerisStreakMiniWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_streakmini_widget).apply {
                setImageViewResource(R.id.widget_mini_fire, R.drawable.ic_fire)
                setImageViewResource(R.id.widget_mini_fire_bg, R.drawable.ic_fire)
                setTextViewText(
                    R.id.widget_streakmini_num,
                    widgetData.getString("streak_num", "0 days") ?: "0 days"
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
