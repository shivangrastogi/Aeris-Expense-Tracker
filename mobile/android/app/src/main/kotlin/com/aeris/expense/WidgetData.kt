package com.aeris.expense

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs

/// One model for every AERIS widget. Flutter (WidgetService) pushes RAW
/// numbers tagged with the day/month they belong to; this object turns them
/// into what a widget should show *right now* — a new day zeroes "today", a
/// new month zeroes "spent", a missed day breaks the streak — so widgets stay
/// correct even when the app hasn't run since yesterday.
object WidgetData {
    class Model(
        val spent: Double,
        val today: Double,
        val budget: Double,
        val streak: Int,
        val week: BooleanArray, // Sun..Sat of the current week
        val todayIdx: Int,
        val aura: Int,
        val town: Int,
        val name: String,
        val hidden: Boolean,
        private val symbol: String,
        private val rate: Double,
        private val indian: Boolean,
        val hasData: Boolean,
    ) {
        val left get() = budget - spent
        val pct get() = if (budget > 0) ((spent / budget) * 100).toInt().coerceIn(0, 999) else 0
        val hasBudget get() = budget > 0
        val checkedInToday get() = week[todayIdx]

        /// "₹12,450" / "₹12.4K" in the user's display currency (amounts are
        /// stored in INR; [rate] is INR per unit), masked when privacy is on.
        fun money(inr: Double, compact: Boolean = false): String {
            if (hidden) return "$symbol••••"
            val v = inr / rate
            val sign = if (v < 0) "-" else ""
            val a = abs(v)
            if (compact && a >= 1000) {
                val (n, unit) = if (indian) when {
                    a >= 1e7 -> a / 1e7 to "Cr"
                    a >= 1e5 -> a / 1e5 to "L"
                    else -> a / 1e3 to "K"
                } else when {
                    a >= 1e9 -> a / 1e9 to "B"
                    a >= 1e6 -> a / 1e6 to "M"
                    else -> a / 1e3 to "K"
                }
                val body = if (n >= 100) n.toInt().toString() else DecimalFormat("0.#").format(n)
                return "$sign$symbol$body$unit"
            }
            return "$sign$symbol${group(Math.round(a))}"
        }

        private fun group(n: Long): String {
            if (!indian) return DecimalFormat("#,##0", DecimalFormatSymbols(Locale.US)).format(n)
            val s = n.toString()
            if (s.length <= 3) return s
            val head = s.dropLast(3)
            val tail = s.takeLast(3)
            return head.reversed().chunked(2).joinToString(",").reversed() + "," + tail
        }

        val firstLine get() = if (name.isNotEmpty()) "Hi, $name" else "AERIS"
    }

    private fun dayKey(c: Calendar) = String.format(
        Locale.US, "%04d-%02d-%02d",
        c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH)
    )

    private fun monthKey(c: Calendar) = String.format(
        Locale.US, "%04d-%02d", c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1
    )

    private fun num(p: SharedPreferences, k: String): Double =
        (try { p.getString(k, null) } catch (_: ClassCastException) { null })?.toDoubleOrNull() ?: 0.0

    private fun int(p: SharedPreferences, k: String): Int =
        try { p.getInt(k, 0) } catch (_: ClassCastException) { 0 }

    private fun bool(p: SharedPreferences, k: String): Boolean =
        try { p.getBoolean(k, false) } catch (_: ClassCastException) { false }

    private fun str(p: SharedPreferences, k: String): String =
        try { p.getString(k, "") ?: "" } catch (_: ClassCastException) { "" }

    fun read(p: SharedPreferences): Model {
        val now = Calendar.getInstance()
        val today = dayKey(now)
        val yesterday = dayKey((now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -1) })

        val sameMonth = str(p, "w_month") == monthKey(now)
        val sameDay = str(p, "w_day") == today

        // Streak is alive only if the last check-in was today or yesterday.
        val last = str(p, "w_last_checkin")
        val streak = if (last == today || last == yesterday) int(p, "w_streak") else 0

        val checkins = str(p, "w_checkins").split(",").filter { it.isNotBlank() }.toSet()
        val todayIdx = now.get(Calendar.DAY_OF_WEEK) - 1 // Sunday = 0
        val sunday = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -todayIdx) }
        val week = BooleanArray(7) { i ->
            val d = (sunday.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, i) }
            dayKey(d) in checkins
        }

        val rate = str(p, "w_cur_rate").toDoubleOrNull()?.takeIf { it > 0 } ?: 1.0
        return Model(
            spent = if (sameMonth) num(p, "w_spent") else 0.0,
            today = if (sameDay) num(p, "w_today") else 0.0,
            budget = num(p, "w_budget"),
            streak = streak,
            week = week,
            todayIdx = todayIdx,
            aura = int(p, "w_aura"),
            town = int(p, "w_town").coerceAtLeast(1),
            name = str(p, "w_name"),
            hidden = bool(p, "w_hidden"),
            symbol = str(p, "w_cur_symbol").ifEmpty { "₹" },
            rate = rate,
            indian = if (p.contains("w_cur_indian")) bool(p, "w_cur_indian") else true,
            hasData = p.contains("w_v"),
        )
    }

    fun isNight(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    private val providers = listOf(
        AerisWidgetProvider::class.java,
        AerisBudgetWidgetProvider::class.java,
        AerisSpentWidgetProvider::class.java,
        AerisTodayWidgetProvider::class.java,
        AerisStreakWidgetProvider::class.java,
        AerisStreakMiniWidgetProvider::class.java,
        AerisVillageWidgetProvider::class.java,
    )

    /// Re-render every placed AERIS widget.
    fun refreshAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        for (cls in providers) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) continue
            context.sendBroadcast(Intent(context, cls).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            })
        }
    }

    /// Wake shortly after the next midnight so "today", the month total and
    /// the streak roll over on time (updatePeriodMillis is at best every 30
    /// min and launchers often stretch it). Inexact on purpose: no exact-alarm
    /// permission needed, and a few minutes' delay is fine.
    fun scheduleMidnight(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val next = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 30)
            set(Calendar.MILLISECOND, 0)
        }
        val pi = PendingIntent.getBroadcast(
            context, 7001, Intent(context, WidgetTickReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.set(AlarmManager.RTC, next.timeInMillis, pi)
    }
}

/// Fired by [WidgetData.scheduleMidnight] (and on time/zone changes):
/// re-render all widgets with the new date, then re-arm for tomorrow.
class WidgetTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WidgetData.refreshAll(context)
        WidgetData.scheduleMidnight(context)
    }
}
