package com.redstarvpn.app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * VpnBridge — Kotlin bridge between Flutter (Dart) and Android native VPN layer.
 *
 * Handles:
 * - MethodChannel: startVpn, stopVpn, getStatus, requestVpnPermission
 * - EventChannel: streams VPN status updates back to Dart
 */
class VpnBridge(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "VpnBridge"
        private const val METHOD_CHANNEL = "com.redstarvpn.app/vpn"
        private const val EVENT_CHANNEL = "com.redstarvpn.app/vpn_status"
        const val VPN_PERMISSION_REQUEST_CODE = 24601

        // Broadcast actions for VPN status updates
        const val ACTION_VPN_STATUS_CHANGED = "com.redstarvpn.app.VPN_STATUS_CHANGED"
        const val EXTRA_VPN_STATUS = "vpn_status"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingConfigJson: String? = null

    // BroadcastReceiver to listen for status changes from SingBoxVpnService
    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val status = intent?.getStringExtra(EXTRA_VPN_STATUS) ?: return
            Log.d(TAG, "Received VPN status broadcast: $status")
            eventSink?.success(status)
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                // Send current status immediately
                eventSink?.success(SingBoxVpnService.currentStatus)
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        // Register broadcast receiver for status updates
        val filter = IntentFilter(ACTION_VPN_STATUS_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(statusReceiver, filter)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startVpn" -> {
                val configJson = call.argument<String>("config")
                if (configJson == null) {
                    result.error("INVALID_ARG", "Config JSON is required", null)
                    return
                }
                startVpn(configJson, result)
            }

            "stopVpn" -> {
                stopVpn(result)
            }

            "getStatus" -> {
                result.success(SingBoxVpnService.currentStatus)
            }

            "requestVpnPermission" -> {
                requestVpnPermission(result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Start VPN connection.
     * First checks VPN permission, then starts the SingBoxVpnService.
     */
    private fun startVpn(configJson: String, result: MethodChannel.Result) {
        Log.d(TAG, "startVpn called, config length: ${configJson.length}")

        // Check if VPN permission is granted
        val intent = VpnService.prepare(activity)
        if (intent != null) {
            // Need to request permission first
            pendingResult = result
            pendingConfigJson = configJson
            activity.startActivityForResult(intent, VPN_PERMISSION_REQUEST_CODE)
            return
        }

        // Permission granted, start VPN service
        doStartVpn(configJson, result)
    }

    /**
     * Actually start the VPN service after permission is confirmed.
     */
    private fun doStartVpn(configJson: String, result: MethodChannel.Result) {
        try {
            val serviceIntent = Intent(activity, SingBoxVpnService::class.java).apply {
                action = SingBoxVpnService.ACTION_START
                putExtra(SingBoxVpnService.EXTRA_CONFIG_JSON, configJson)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(serviceIntent)
            } else {
                activity.startService(serviceIntent)
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN service", e)
            result.error("START_FAILED", e.message, null)
        }
    }

    /**
     * Stop VPN connection.
     */
    private fun stopVpn(result: MethodChannel.Result) {
        try {
            val serviceIntent = Intent(activity, SingBoxVpnService::class.java).apply {
                action = SingBoxVpnService.ACTION_STOP
            }
            activity.startService(serviceIntent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop VPN service", e)
            result.error("STOP_FAILED", e.message, null)
        }
    }

    /**
     * Request VPN permission explicitly.
     */
    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(activity)
        if (intent != null) {
            pendingResult = result
            pendingConfigJson = null
            activity.startActivityForResult(intent, VPN_PERMISSION_REQUEST_CODE)
        } else {
            // Already granted
            result.success(true)
        }
    }

    /**
     * Handle VPN permission result from activity.
     * Call this from MainActivity.onActivityResult().
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode == VPN_PERMISSION_REQUEST_CODE) {
            val result = pendingResult
            val configJson = pendingConfigJson
            pendingResult = null
            pendingConfigJson = null

            if (resultCode == Activity.RESULT_OK) {
                if (configJson != null && result != null) {
                    // Permission granted, now start VPN
                    doStartVpn(configJson, result)
                } else {
                    result?.success(true)
                }
            } else {
                result?.error(
                    "PERMISSION_DENIED",
                    "Пользователь отклонил VPN-разрешение",
                    null
                )
            }
        }
    }

    fun dispose() {
        try {
            activity.unregisterReceiver(statusReceiver)
        } catch (e: Exception) {
            // Receiver might not be registered
        }
        methodChannel.setMethodCallHandler(null)
    }
}
