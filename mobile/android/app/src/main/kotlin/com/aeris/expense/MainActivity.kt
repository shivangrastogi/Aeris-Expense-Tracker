package com.aeris.expense

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth so
// the biometric prompt can attach to a FragmentActivity host.
//
// Also hosts a lightweight bridge to Android's built-in SpeechRecognizer for
// the in-app voice transaction entry (no third-party plugin — speech_to_text is
// incompatible with this Flutter/embedding version). Mic permission is requested
// from Dart (permission_handler) before `start` is called.
class MainActivity : FlutterFragmentActivity() {
    private var speech: SpeechRecognizer? = null
    private var events: EventChannel.EventSink? = null
    private var pendingLocale: String? = null

    companion object {
        private const val MIC_REQ = 4823
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "aeris/voice/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                }
                override fun onCancel(args: Any?) {
                    events = null
                }
            },
        )

        MethodChannel(messenger, "aeris/voice").setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" ->
                    result.success(SpeechRecognizer.isRecognitionAvailable(this))
                "start" -> {
                    requestMicThenStart(call.argument<String>("locale"))
                    result.success(true)
                }
                "stop" -> {
                    speech?.stopListening()
                    result.success(true)
                }
                "cancel" -> {
                    speech?.cancel()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun emit(map: Map<String, Any?>) {
        runOnUiThread { events?.success(map) }
    }

    private fun requestMicThenStart(locale: String?) {
        pendingLocale = locale
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            == PackageManager.PERMISSION_GRANTED
        ) {
            startListening(locale)
        } else {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQ,
            )
        }
    }

    // Handle our mic-permission result ourselves and CONSUME it (no super) so it
    // is never forwarded to the Flutter plugins — another_telephony's handler
    // would otherwise re-reply a stale result and crash ("Reply already
    // submitted"). Other request codes fall through to the plugins as usual.
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == MIC_REQ) {
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            ) {
                startListening(pendingLocale)
            } else {
                emit(mapOf("type" to "error", "value" to "denied"))
            }
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun startListening(locale: String?) {
        speech?.destroy()
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            emit(mapOf("type" to "error", "value" to "unavailable"))
            return
        }
        speech = SpeechRecognizer.createSpeechRecognizer(this)
        speech?.setRecognitionListener(
            object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) =
                    emit(mapOf("type" to "status", "value" to "ready"))
                override fun onBeginningOfSpeech() =
                    emit(mapOf("type" to "status", "value" to "listening"))
                override fun onRmsChanged(rmsdB: Float) =
                    emit(mapOf("type" to "rms", "value" to rmsdB.toDouble()))
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() =
                    emit(mapOf("type" to "status", "value" to "processing"))
                override fun onError(error: Int) =
                    emit(mapOf("type" to "error", "value" to error.toString()))
                override fun onResults(results: Bundle?) {
                    val text = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull() ?: ""
                    emit(mapOf("type" to "final", "value" to text))
                }
                override fun onPartialResults(partial: Bundle?) {
                    val text = partial
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull() ?: ""
                    emit(mapOf("type" to "partial", "value" to text))
                }
                override fun onEvent(eventType: Int, params: Bundle?) {}
            },
        )
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale ?: "en-IN")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        speech?.startListening(intent)
    }

    override fun onDestroy() {
        speech?.destroy()
        speech = null
        super.onDestroy()
    }
}
