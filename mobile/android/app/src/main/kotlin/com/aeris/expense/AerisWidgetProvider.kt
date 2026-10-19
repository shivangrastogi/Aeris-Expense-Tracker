package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 3x2 overview: left to spend this month, a progress bar, today, streak.
class AerisWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val m = WidgetData.read(widgetData)
        WidgetData.scheduleMidnight(context)
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_widget).apply {
                val over = m.hasBudget && m.left < 0
                setTextViewText(R.id.widget_title, when {
                    !m.hasBudget -> "Spent this month"
                    over -> "Over budget"
                    else -> "Left to spend"
                })
                setTextViewText(R.id.widget_amount, when {
                    !m.hasData -> "—"
                    !m.hasBudget -> m.money(m.spent)
                    else -> m.money(kotlin.math.abs(m.left))
                })
                setTextColor(R.id.widget_amount, context.getColor(
                    if (over) R.color.w_danger else R.color.w_text))
                setProgressBar(R.id.widget_progress, 100, m.pct.coerceAtMost(100), false)
                setViewVisibility(R.id.widget_progress, if (m.hasBudget && !over) android.view.View.VISIBLE else android.view.View.GONE)
                setViewVisibility(R.id.widget_progress_over, if (over) android.view.View.VISIBLE else android.view.View.GONE)
                setTextViewText(R.id.widget_sub, when {
                    !m.hasData -> "Open AERIS to sync"
                    m.hasBudget -> "${m.money(m.spent, true)} of ${m.money(m.budget, true)} · today ${m.money(m.today, true)}"
                    else -> "Today ${m.money(m.today, true)} · set a budget in AERIS"
                })
                setTextViewText(R.id.widget_streak_text, "${m.streak}")
                setInt(R.id.widget_fire, "setColorFilter", context.getColor(
                    if (m.streak > 0) R.color.w_warn else R.color.w_muted))
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("aeriswidget://budgets")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
