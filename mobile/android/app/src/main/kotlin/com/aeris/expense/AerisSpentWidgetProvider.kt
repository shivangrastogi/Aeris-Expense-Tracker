package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 2x2 this month's spend, against the budget, plus today.
class AerisSpentWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val m = WidgetData.read(widgetData)
        WidgetData.scheduleMidnight(context)
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_spent_widget).apply {
                setTextViewText(R.id.widget_spent_amount, if (m.hasData) m.money(m.spent) else "—")
                setTextViewText(R.id.widget_spent_sub,
                    if (m.hasBudget) "of ${m.money(m.budget, true)} budget (${m.pct}%)" else "No budget set")
                setTextViewText(R.id.widget_spent_today, "Today ${m.money(m.today, true)}")
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("aeriswidget://activity")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
