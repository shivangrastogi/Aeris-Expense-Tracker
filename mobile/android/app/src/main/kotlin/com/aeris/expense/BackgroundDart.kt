package com.aeris.expense

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/// Runs Dart's `widgetBackgroundMain` (lib/main.dart → widget_background.dart)
/// in a headless Flutter engine, so widgets refresh — and UPI-app payments
/// get saved — while the app itself is closed. One run at a time; a request
/// that arrives mid-run queues exactly one more run after it.
object BackgroundDart {
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var again = false
    private val waiters = ArrayList<() -> Unit>()

    /// [onDone] is called (on the main thread) once the run has finished.
    fun run(context: Context, onDone: (() -> Unit)? = null) {
        val app = context.applicationContext
        main.post {
            onDone?.let { waiters.add(it) }
            if (engine != null) again = true else start(app)
        }
    }

    private fun start(app: Context) {
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(app)
            loader.ensureInitializationComplete(app, null)
            val e = FlutterEngine(app) // registers every plugin
            engine = e
            MethodChannel(e.dartExecutor.binaryMessenger, "aeris/bg")
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "drain" -> result.success(UpiNotificationListener.drain(app))
                        "done" -> {
                            result.success(null)
                            main.post { finish(app, e) }
                        }
                        else -> result.notImplemented()
                    }
                }
            // Safety net: never keep an engine alive if Dart hangs.
            main.postDelayed({ finish(app, e) }, 90_000)
            e.dartExecutor.executeDartEntrypoint(
                // In main.dart: a release build drops libraries main.dart
                // doesn't import, so the function can't live elsewhere.
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "widgetBackgroundMain"),
            )
        } catch (_: Throwable) {
            engine?.destroy()
            engine = null
            WidgetData.refreshAll(app) // at least roll the dates over
            release()
        }
    }

    private fun finish(app: Context, e: FlutterEngine) {
        if (engine !== e) return // already finished (or timed out)
        engine = null
        e.destroy()
        WidgetData.refreshAll(app)
        if (again) {
            again = false
            start(app)
        } else {
            release()
        }
    }

    private fun release() {
        val w = ArrayList(waiters)
        waiters.clear()
        w.forEach { it() }
    }
}

/// Every ~30 minutes while an AERIS widget is on the home screen: recompute
/// the widget numbers from the real data (see [BackgroundDart]). WorkManager
/// survives reboots and app updates on its own.
class WidgetRefreshWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        if (!WidgetData.anyPlaced(applicationContext)) {
            cancel(applicationContext) // no widgets left: stop waking up
            return Result.success()
        }
        val latch = CountDownLatch(1)
        BackgroundDart.run(applicationContext) { latch.countDown() }
        latch.await(100, TimeUnit.SECONDS)
        return Result.success()
    }

    companion object {
        private const val NAME = "aeris_widget_refresh"

        fun schedule(context: Context) {
            val req = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(30, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, req)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context.applicationContext).cancelUniqueWork(NAME)
        }
    }
}
