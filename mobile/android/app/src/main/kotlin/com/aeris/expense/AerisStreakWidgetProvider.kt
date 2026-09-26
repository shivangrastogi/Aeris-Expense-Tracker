package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 4x2 streak widget — orange card with "N days / Streak" and a 7-day dot row
/// filled to the current streak, matching the in-app gallery preview.
class AerisStreakWidgetProvider : HomeWidgetProvider() {
    private val dotIds = intArrayOf(
        R.id.widget_dot_0, R.id.widget_dot_1, R.id.widget_dot_2, R.id.widget_dot_3,
        R.id.widget_dot_4, R.id.widget_dot_5, R.id.widget_dot_6
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val streak = widgetData.getInt("streak_count", 0)
        val greeting = widgetData.getString("streak_greeting", "") ?: ""
        // Real Sun→Sat check-in state ("1,0,1,…") + today's column, pushed by
        // WidgetService. Falls back to the old positional fill if absent.
        val weekStr = widgetData.getString("streak_week", "") ?: ""
        val today = widgetData.getInt("streak_today", -1)
        val days = weekStr.split(",").map { it.trim() == "1" }
        val haveWeek = days.size == 7
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_streak_widget).apply {
                // Set the flame vectors explicitly (more reliable than relying on
                // android:src in the RemoteViews XML across launchers).
                setImageViewResource(R.id.widget_fire, R.drawable.ic_fire)
                setImageViewResource(R.id.widget_fire_bg, R.drawable.ic_fire)
                setTextViewText(
                    R.id.widget_streak_count,
                    "$streak day" + if (streak == 1) "" else "s"
                )
                if (greeting.isNotEmpty()) {
                    setTextViewText(R.id.widget_greeting, greeting)
                    setViewVisibility(R.id.widget_greeting, android.view.View.VISIBLE)
                } else {
                    setViewVisibility(R.id.widget_greeting, android.view.View.GONE)
                }
                for (i in dotIds.indices) {
                    // Prefer the real calendar week; fall back to positional
                    // fill only when no week data was pushed yet.
                    val on = if (haveWeek) days[i] else i < streak.coerceIn(0, 7)
                    val isToday = haveWeek && i == today
                    val bg = when {
                        on -> R.drawable.aeris_dot_on
                        isToday -> R.drawable.aeris_dot_today
                        else -> R.drawable.aeris_dot_off
                    }
                    setInt(dotIds[i], "setBackgroundResource", bg)
                    setTextViewText(dotIds[i], if (on) "✓" else "")
                }
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
