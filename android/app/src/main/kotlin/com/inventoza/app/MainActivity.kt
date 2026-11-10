package com.inventoza.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.raj_electricals/upi"
    private val UPI_REQUEST = 1299
    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        enableHighRefreshRate()
    }

    private fun enableHighRefreshRate() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val modes = display?.supportedModes
                val maxMode = modes?.maxByOrNull { it.refreshRate }
                if (maxMode != null) {
                    val params = window.attributes
                    params.preferredDisplayModeId = maxMode.modeId
                    window.attributes = params
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                @Suppress("DEPRECATION")
                val display = windowManager.defaultDisplay
                val modes = display.supportedModes
                val maxMode = modes?.maxByOrNull { it.refreshRate }
                if (maxMode != null) {
                    val params = window.attributes
                    params.preferredDisplayModeId = maxMode.modeId
                    window.attributes = params
                }
            }
        } catch (_: Exception) {
            // Ignore if display mode switching is not supported on device
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startUpiPayment" -> {
                        if (pendingResult != null) {
                            result.error("ALREADY_ACTIVE", "A UPI transaction is already in progress", null)
                            return@setMethodCallHandler
                        }
                        val uriStr = call.argument<String>("uri")
                        if (uriStr.isNullOrBlank()) {
                            result.error("ARG_ERROR", "Missing or empty 'uri' argument", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uriStr))
                        // Let Android show chooser of capable UPI apps
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        pendingResult = result
                        try {
                            startActivityForResult(intent, UPI_REQUEST)
                        } catch (e: Exception) {
                            pendingResult = null
                            result.error("LAUNCH_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == UPI_REQUEST) {
            val res = pendingResult
            pendingResult = null
            if (res == null) return

            // Many UPI apps return a 'response' extra in the format 'txnId=..&Status=SUCCESS&txnRef=..&ApprovalRefNo=..'
            val raw = data?.getStringExtra("response") ?: data?.dataString ?: ""
            val map = HashMap<String, String>()
            if (raw.isNotBlank()) {
                val parts = raw.split("&")
                for (p in parts) {
                    val kv = p.split("=")
                    if (kv.isNotEmpty()) {
                        val key = kv[0]
                        val value = if (kv.size >= 2) kv.subList(1, kv.size).joinToString("=") else ""
                        map[key] = value
                    }
                }
            }
            val lower = raw.lowercase()
            val status = when {
                lower.contains("success") -> "SUCCESS"
                lower.contains("fail") -> "FAILURE"
                lower.contains("submitted") -> "SUBMITTED"
                raw.isBlank() -> "CANCELLED"
                else -> "UNKNOWN"
            }
            map["status"] = status
            res.success(map)
        }
    }
}

