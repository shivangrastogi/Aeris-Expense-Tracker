package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 1x1 today's spend (resets itself at midnight).
class AerisTodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val m = WidgetData.read(widgetData)
        WidgetData.keepFresh(context)
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_today_widget).apply {
                setTextViewText(R.id.widget_today_amount, if (m.hasData) m.money(m.today, true) else "—")
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("aeriswidget://activity")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
