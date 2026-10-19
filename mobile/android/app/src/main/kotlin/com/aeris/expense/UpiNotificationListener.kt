package com.aeris.expense

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * Catches payment notifications from UPI apps (Google Pay, PhonePe, Paytm…),
 * which often send no SMS at all. Only the listed apps are read; each
 * notification's title + text is queued on-device and handed to Dart, which
 * parses it with the same pipeline as bank SMS. Nothing leaves the phone.
 *
 * Runs whenever the user has granted notification access, app open or not;
 * the queue is drained the next time the app is open (immediately, if it is).
 */
class UpiNotificationListener : NotificationListenerService() {

    companion object {
        const val PREFS = "aeris_notif"
        private const val KEY = "queue"
        private const val MAX = 200

        /** Package → the sender name Dart's parser trusts. */
        val APPS = mapOf(
            "com.google.android.apps.nbu.paisa.user" to "GPAY",
            "com.phonepe.app" to "PHONEPE",
            "net.one97.paytm" to "PAYTM",
            "in.org.npci.upiapp" to "BHIM",
            "in.amazon.mShop.android.shopping" to "APAY",
            "com.dreamplug.androidapp" to "CRED",
            "com.mobikwik_new" to "MOBIKWIK",
            "com.naviapp" to "NAVI",
            "money.super.payments" to "SUPERMONEY",
            "com.slice" to "SLICE",
            "money.jupiter" to "JUPITER",
            "com.epifi.paisa" to "EPIFI",
        )

        /** Set by MainActivity while the Flutter engine is alive. */
        @Volatile
        var onQueued: (() -> Unit)? = null

        @Synchronized
        fun drain(ctx: Context): List<Map<String, Any>> {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString(KEY, "[]"))
            prefs.edit().remove(KEY).apply()
            val out = ArrayList<Map<String, Any>>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                out.add(
                    mapOf(
                        "app" to o.getString("app"),
                        "title" to o.optString("title"),
                        "text" to o.optString("text"),
                        "ts" to o.getLong("ts"),
                    ),
                )
            }
            return out
        }

        @Synchronized
        private fun enqueue(ctx: Context, item: JSONObject) {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString(KEY, "[]"))
            // The same notification is often re-posted (updated); keep one.
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (o.optString("title") == item.optString("title") &&
                    o.optString("text") == item.optString("text")
                ) return
            }
            arr.put(item)
            val trimmed = JSONArray()
            val start = maxOf(0, arr.length() - MAX)
            for (i in start until arr.length()) trimmed.put(arr.get(i))
            prefs.edit().putString(KEY, trimmed.toString()).apply()
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val app = APPS[sbn.packageName] ?: return
        val n = sbn.notification ?: return
        // Group summaries and ongoing (progress) notifications aren't payments.
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (n.flags and Notification.FLAG_ONGOING_EVENT != 0) return
        val extras = n.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString() ?: ""
        if (text.isBlank() && title.isBlank()) return
        // Cheap pre-filter: a payment always names an amount.
        if (!Regex("(₹|rs\\.?|inr)\\s*\\d", RegexOption.IGNORE_CASE).containsMatchIn("$title $text")) return
        enqueue(
            this,
            JSONObject()
                .put("app", app)
                .put("title", title)
                .put("text", text)
                .put("ts", sbn.postTime),
        )
        onQueued?.invoke()
    }
}
