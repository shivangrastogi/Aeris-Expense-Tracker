package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Quick-capture 4x1 widget. Each action launches the app with a uri the
/// Flutter side routes (aeriswidget://quickadd | aeriswidget://voice).
class AerisQuickWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.aeris_quick_widget).apply {
                // Draw the Aeris-style avatar (teal blob + smiley) so it reads as
                // an avatar, not a plain circle. Icons set explicitly too.
                setImageViewBitmap(R.id.widget_quick_avatar, avatarBitmap())
                setImageViewResource(R.id.widget_quick_voice, R.drawable.ic_mic)
                setImageViewResource(R.id.widget_quick_add, R.drawable.ic_add)
                setOnClickPendingIntent(
                    R.id.widget_quick_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("aeriswidget://quickadd")
                    )
                )
                setOnClickPendingIntent(
                    R.id.widget_quick_add,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("aeriswidget://quickadd")
                    )
                )
                setOnClickPendingIntent(
                    R.id.widget_quick_voice,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("aeriswidget://voice")
                    )
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /// Teal gradient circle with two eyes and a smile — a compact stand-in for
    /// the in-app Aeris avatar.
    private fun avatarBitmap(): Bitmap {
        val px = 96
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val r = px / 2f

        val body = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f, 0f, px.toFloat(), px.toFloat(),
                Color.parseColor("#19C2B6"), Color.parseColor("#0F766E"),
                Shader.TileMode.CLAMP
            )
        }
        canvas.drawCircle(r, r, r, body)

        // little sprout stem
        val stem = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0B4A47")
            strokeWidth = px * 0.05f
            strokeCap = Paint.Cap.ROUND
        }
        canvas.drawLine(r, px * 0.16f, r, px * 0.04f, stem)

        val face = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0B4A47")
        }
        val eyeR = px * 0.055f
        canvas.drawCircle(px * 0.37f, px * 0.46f, eyeR, face)
        canvas.drawCircle(px * 0.63f, px * 0.46f, eyeR, face)

        val smile = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0B4A47")
            style = Paint.Style.STROKE
            strokeWidth = px * 0.05f
            strokeCap = Paint.Cap.ROUND
        }
        val mouth = RectF(px * 0.36f, px * 0.5f, px * 0.64f, px * 0.7f)
        canvas.drawArc(mouth, 20f, 140f, false, smile)
        return bmp
    }
}
