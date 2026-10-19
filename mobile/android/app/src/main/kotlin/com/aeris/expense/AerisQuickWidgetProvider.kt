package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 4x1 quick capture. Bar → type a sentence (quick add), mic → voice,
/// + → the full expense form. Flutter routes the aeriswidget:// links.
class AerisQuickWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.aeris_quick_widget).apply {
                setImageViewBitmap(R.id.widget_quick_avatar, orb(context))
                setInt(R.id.widget_quick_voice, "setColorFilter", context.getColor(R.color.w_text))
                setInt(R.id.widget_quick_add, "setColorFilter", context.getColor(R.color.w_on_accent))
                setOnClickPendingIntent(R.id.widget_quick_root, link(context, "quickadd"))
                setOnClickPendingIntent(R.id.widget_quick_voice, link(context, "voice"))
                setOnClickPendingIntent(R.id.widget_quick_add, link(context, "add"))
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun link(context: Context, host: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("aeriswidget://$host"))

    /// Small glowing accent orb — the AERIS mark.
    private fun orb(context: Context): Bitmap {
        val px = 72
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val accent = context.getColor(R.color.w_accent)
        val r = px / 2f
        c.drawCircle(r, r, r, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(r * 0.75f, r * 0.7f, r, intArrayOf(0xFFFFFFFF.toInt(), accent, 0x00000000),
                floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP)
        })
        return bmp
    }
}
