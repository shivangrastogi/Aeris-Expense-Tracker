package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF

/// 2x2 budget ring: % of this month's budget used, amount left.
class AerisBudgetWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val m = WidgetData.read(widgetData)
        WidgetData.scheduleMidnight(context)
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aeris_budget_widget).apply {
                val over = m.left < 0
                setImageViewBitmap(R.id.widget_ring, ring(context, m))
                setTextViewText(R.id.widget_ring_left, when {
                    !m.hasBudget -> "No budget"
                    else -> m.money(kotlin.math.abs(m.left), true)
                })
                setTextColor(R.id.widget_ring_left, context.getColor(
                    if (m.hasBudget && over) R.color.w_danger else R.color.w_text))
                setTextViewText(R.id.widget_ring_cap, when {
                    !m.hasBudget -> "tap to set one"
                    over -> "over budget"
                    else -> "left this month"
                })
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("aeriswidget://budgets")))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /// Rounded ring filled to the % used; accent → amber at 80% → red over.
    private fun ring(context: Context, m: WidgetData.Model): Bitmap {
        val px = 220
        val stroke = 20f
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val pad = stroke / 2f + 2f
        val rect = RectF(pad, pad, px - pad, px - pad)
        fun col(id: Int) = context.getColor(id)
        val fill = when {
            m.pct >= 100 -> col(R.color.w_danger)
            m.pct >= 80 -> col(R.color.w_warn)
            else -> col(R.color.w_accent)
        }
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = stroke; strokeCap = Paint.Cap.ROUND
        }
        p.color = col(R.color.w_track)
        c.drawArc(rect, 0f, 360f, false, p)
        if (m.hasBudget && m.pct > 0) {
            p.color = fill
            c.drawArc(rect, -90f, m.pct.coerceAtMost(100) / 100f * 360f, false, p)
        }
        val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = col(R.color.w_text)
            textAlign = Paint.Align.CENTER
            textSize = 52f
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
        }
        val label = if (m.hasBudget) "${m.pct}%" else "—"
        c.drawText(label, px / 2f, px / 2f - (t.descent() + t.ascent()) / 2f, t)
        return bmp
    }
}
