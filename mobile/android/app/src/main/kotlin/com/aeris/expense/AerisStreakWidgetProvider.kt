package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 4x2 check-in streak with the last 7 days (today on the right); the button
/// opens a check-in.
class AerisStreakWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val m = WidgetData.read(widgetData)
        WidgetData.keepFresh(context)
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_streak_widget).apply {
                setTextViewText(R.id.widget_streak_count, "${m.streak} day" + if (m.streak == 1) "" else "s")
                setTextViewText(R.id.widget_greeting, when {
                    m.checkedInToday -> "Checked in today. See you tomorrow."
                    m.streak > 0 -> "${if (m.name.isNotEmpty()) "${m.name}, c" else "C"}heck in to keep it going"
                    else -> "Check in daily to build a streak"
                })
                setInt(R.id.widget_fire, "setColorFilter", context.getColor(
                    if (m.streak > 0) R.color.w_warn else R.color.w_muted))
                setViewVisibility(R.id.widget_checkin,
                    if (m.checkedInToday) android.view.View.GONE else android.view.View.VISIBLE)
                for (i in dots.indices) {
                    val on = m.week[i]
                    val bg = when {
                        on -> R.drawable.w_dot_on
                        i == m.todayIdx -> R.drawable.w_dot_today
                        else -> R.drawable.w_dot_off
                    }
                    setInt(dots[i], "setBackgroundResource", bg)
                    setTextViewText(dots[i], if (on) "✓" else "")
                    setTextViewText(days[i], m.dayLetters[i])
                    setTextColor(days[i], context.getColor(
                        if (i == m.todayIdx) R.color.w_text else R.color.w_muted))
                }
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("aeriswidget://checkin")))
                setOnClickPendingIntent(R.id.widget_checkin, HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("aeriswidget://checkin")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private val dots = intArrayOf(
        R.id.widget_dot_0, R.id.widget_dot_1, R.id.widget_dot_2, R.id.widget_dot_3,
        R.id.widget_dot_4, R.id.widget_dot_5, R.id.widget_dot_6
    )
    private val days = intArrayOf(
        R.id.widget_day_0, R.id.widget_day_1, R.id.widget_day_2, R.id.widget_day_3,
        R.id.widget_day_4, R.id.widget_day_5, R.id.widget_day_6
    )
}
