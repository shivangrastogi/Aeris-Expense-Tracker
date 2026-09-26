package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 2x2 "Budget" widget — a glass card with a real circular progress ring drawn
/// on a Canvas (RemoteViews can't custom-paint, so we render a bitmap) plus the
/// remaining amount, mirroring the in-app preview.
class AerisBudgetWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val pct = widgetData.getInt("pct", 0).coerceIn(0, 100)
        val leftText = widgetData.getString("ring_left_text", "—") ?: "—"
        val isOver = widgetData.getBoolean("ring_is_over", false)

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.aeris_budget_widget).apply {
                setImageViewBitmap(R.id.widget_ring, ringBitmap(pct))
                setTextViewText(R.id.widget_ring_left, leftText)
                setTextColor(
                    R.id.widget_ring_left,
                    if (isOver) Color.parseColor("#E5484D") else Color.parseColor("#15A24A")
                )
                setTextViewText(R.id.widget_ring_cap, if (isOver) "over" else "left")
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /// Draws a rounded-cap ring filled to [pct]%, with the percentage in the
    /// centre. Colour shifts seed → amber → red as it approaches/exceeds 100%.
    private fun ringBitmap(pct: Int): Bitmap {
        val px = 148
        val stroke = 16f
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val pad = stroke / 2f + 2f
        val rect = RectF(pad, pad, px - pad, px - pad)

        val ringColor = when {
            pct >= 100 -> Color.parseColor("#E5484D")
            pct >= 80 -> Color.parseColor("#E08C00")
            else -> Color.parseColor("#0EA5A4")
        }

        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            color = Color.parseColor("#22142838")
        }
        canvas.drawArc(rect, 0f, 360f, false, track)

        val prog = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            color = ringColor
        }
        canvas.drawArc(rect, -90f, pct / 100f * 360f, false, prog)

        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#142838")
            textAlign = Paint.Align.CENTER
            textSize = 38f
            isFakeBoldText = true
        }
        val cy = px / 2f - (text.descent() + text.ascent()) / 2f
        canvas.drawText("$pct%", px / 2f, cy, text)
        return bmp
    }
}
