package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 2x1 streak count.
class AerisStreakMiniWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val m = WidgetData.read(widgetData)
        WidgetData.scheduleMidnight(context)
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_streakmini_widget).apply {
                setTextViewText(R.id.widget_streakmini_num, "${m.streak} day" + if (m.streak == 1) "" else "s")
                setTextViewText(R.id.widget_streakmini_sub,
                    if (m.checkedInToday) "streak · done today" else "streak · tap to check in")
                setInt(R.id.widget_mini_fire, "setColorFilter", context.getColor(
                    if (m.streak > 0) R.color.w_warn else R.color.w_muted))
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("aeriswidget://checkin")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
