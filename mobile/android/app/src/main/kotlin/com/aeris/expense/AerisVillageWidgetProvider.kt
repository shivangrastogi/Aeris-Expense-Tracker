package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 2x2 Aeris Town: level and Aura to spend.
class AerisVillageWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val m = WidgetData.read(widgetData)
        WidgetData.scheduleMidnight(context)
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_village_widget).apply {
                setTextViewText(R.id.widget_village_lvl, "Level ${m.town}")
                setTextViewText(R.id.widget_village_aura, "%,d Aura".format(m.aura))
                setTextViewText(R.id.widget_village_sub,
                    if (m.checkedInToday) "Spend Aura to grow your town" else "Check in today for Aura")
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("aeriswidget://village")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
