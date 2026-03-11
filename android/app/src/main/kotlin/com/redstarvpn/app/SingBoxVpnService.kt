package com.redstarvpn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/**
 * SingBoxVpnService — Android VpnService that runs sing-box core
 * to establish a VPN tunnel.
 *
 * For the MVP, sing-box is launched as a subprocess using the
 * prebuilt sing-box binary included in the app's native libs.
 *
 * Architecture:
 * 1. Receives sing-box JSON config from Flutter via intent extras
 * 2. Writes config to app's private directory
 * 3. Establishes TUN interface via VpnService.Builder
 * 4. Launches sing-box process with the config
 * 5. Monitors process lifecycle and broadcasts status changes
 *
 * Alternative approach (for production):
 * Use sing-box's libbox (Go mobile library) directly via JNI/Gomobile bindings.
 * For MVP, the subprocess approach is simpler and faster to implement.
 */
class SingBoxVpnService : VpnService() {

    companion object {
        private const val TAG = "SingBoxVpnService"
        const val ACTION_START = "com.redstarvpn.app.START_VPN"
        const val ACTION_STOP = "com.redstarvpn.app.STOP_VPN"
        const val EXTRA_CONFIG_JSON = "config_json"

        private const val NOTIFICATION_CHANNEL_ID = "redstar_vpn_channel"
        private const val NOTIFICATION_ID = 1

        // Current VPN status — accessible from VpnBridge
        @Volatile
        var currentStatus: String = "disconnected"
            private set
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var singBoxProcess: Process? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var configFile: File? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val configJson = intent.getStringExtra(EXTRA_CONFIG_JSON)
                if (configJson != null) {
                    startVpn(configJson)
                } else {
                    Log.e(TAG, "No config JSON provided")
                    updateStatus("error")
                    stopSelf()
                }
            }
            ACTION_STOP -> {
                stopVpn()
            }
            else -> {
                Log.w(TAG, "Unknown action: ${intent?.action}")
            }
        }
        return START_STICKY
    }

    private fun startVpn(configJson: String) {
        serviceScope.launch {
            try {
                updateStatus("connecting")

                // Start foreground service with notification
                withContext(Dispatchers.Main) {
                    startForeground(NOTIFICATION_ID, buildNotification("Подключение..."))
                }

                // Write config to file
                val config = writeConfigFile(configJson)
                configFile = config

                // Modify config to remove TUN inbound (we manage TUN ourselves)
                // and adjust for the VpnService fd approach
                val modifiedConfig = adjustConfigForVpnService(configJson)
                config.writeText(modifiedConfig)

                // Establish TUN interface
                val tun = establishTunInterface()
                if (tun == null) {
                    Log.e(TAG, "Failed to establish TUN interface")
                    updateStatus("error")
                    stopSelf()
                    return@launch
                }
                vpnInterface = tun

                // Find sing-box binary
                val singBoxBinary = findSingBoxBinary()
                if (singBoxBinary == null) {
                    Log.e(TAG, "sing-box binary not found")
                    updateStatus("error")
                    stopSelf()
                    return@launch
                }

                // Launch sing-box process
                val process = launchSingBox(singBoxBinary, config, tun.fd)
                singBoxProcess = process

                // Wait a moment for sing-box to initialize
                delay(1500)

                // Check if process is still running
                if (process.isAlive) {
                    updateStatus("connected")
                    withContext(Dispatchers.Main) {
                        startForeground(NOTIFICATION_ID, buildNotification("Подключено ✓"))
                    }

                    // Monitor process
                    monitorProcess(process)
                } else {
                    val exitCode = process.exitValue()
                    Log.e(TAG, "sing-box exited prematurely with code: $exitCode")

                    // Read stderr for error details
                    val error = process.errorStream.bufferedReader().readText()
                    Log.e(TAG, "sing-box error: $error")

                    updateStatus("error")
                    stopSelf()
                }

            } catch (e: Exception) {
                Log.e(TAG, "Failed to start VPN", e)
                updateStatus("error")
                stopSelf()
            }
        }
    }

    /**
     * Write sing-box config JSON to app's files directory.
     */
    private fun writeConfigFile(configJson: String): File {
        val configDir = File(filesDir, "sing-box")
        configDir.mkdirs()
        val configFile = File(configDir, "config.json")
        FileOutputStream(configFile).use { fos ->
            fos.write(configJson.toByteArray())
        }
        Log.d(TAG, "Config written to: ${configFile.absolutePath}")
        return configFile
    }

    /**
     * Adjust sing-box config for Android VpnService usage.
     * Remove the TUN inbound (since we provide the fd ourselves),
     * or keep it if sing-box handles TUN natively.
     *
     * For the MVP subprocess approach, we configure sing-box
     * to use the TUN interface we created.
     */
    private fun adjustConfigForVpnService(configJson: String): String {
        // For MVP: keep the config as-is since sing-box manages TUN internally.
        // The key is that we call protect() on sing-box's sockets to prevent loops.
        // In subprocess mode, sing-box uses its own TUN stack.
        // We create a VpnService-based TUN and sing-box runs with --tun-fd.
        //
        // Actually, for the simplest MVP approach:
        // Let sing-box manage everything including TUN creation.
        // We just need the VpnService to authorize the TUN.
        return configJson
    }

    /**
     * Establish TUN interface via Android VpnService.Builder.
     */
    private fun establishTunInterface(): ParcelFileDescriptor? {
        try {
            val builder = Builder()
                .setSession("Red Star VPN")
                .setMtu(1500)
                .addAddress("172.19.0.1", 30)
                .addRoute("0.0.0.0", 0)       // Route all IPv4 traffic
                .addRoute("::", 0)              // Route all IPv6 traffic
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")

            // Exclude the app itself from VPN to prevent loops
            // (sing-box process needs direct internet access)
            try {
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to disallow application: $e")
            }

            val pfd = builder.establish()
            if (pfd != null) {
                Log.d(TAG, "TUN interface established, fd: ${pfd.fd}")
            }
            return pfd
        } catch (e: Exception) {
            Log.e(TAG, "Failed to build TUN interface", e)
            return null
        }
    }

    /**
     * Find the sing-box binary.
     * In production, this would be bundled in the APK's native libs.
     * For MVP, we can include it as an asset and extract on first run.
     */
    private fun findSingBoxBinary(): File? {
        // Check multiple possible locations
        val possiblePaths = listOf(
            File(applicationInfo.nativeLibraryDir, "libsing-box.so"),
            File(applicationInfo.nativeLibraryDir, "libsingbox.so"),
            File(filesDir, "sing-box/sing-box"),
            File(filesDir, "sing-box"),
        )

        for (path in possiblePaths) {
            if (path.exists() && path.canExecute()) {
                Log.d(TAG, "Found sing-box binary: ${path.absolutePath}")
                return path
            }
        }

        // Try to extract from assets
        return extractSingBoxFromAssets()
    }

    /**
     * Extract sing-box binary from APK assets.
     * The binary should be placed in android/app/src/main/assets/sing-box
     * or bundled as a native library.
     */
    private fun extractSingBoxFromAssets(): File? {
        try {
            val targetFile = File(filesDir, "sing-box/sing-box")
            if (targetFile.exists()) {
                targetFile.setExecutable(true)
                return targetFile
            }

            targetFile.parentFile?.mkdirs()

            // Try to copy from assets
            val assetName = "sing-box"
            assets.open(assetName).use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }
            targetFile.setExecutable(true)
            Log.d(TAG, "Extracted sing-box to: ${targetFile.absolutePath}")
            return targetFile
        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract sing-box from assets: $e")
            return null
        }
    }

    /**
     * Launch sing-box subprocess with the given config.
     */
    private fun launchSingBox(binary: File, config: File, tunFd: Int): Process {
        val command = listOf(
            binary.absolutePath,
            "run",
            "-c", config.absolutePath,
        )

        Log.d(TAG, "Launching sing-box: ${command.joinToString(" ")}")

        val processBuilder = ProcessBuilder(command)
            .directory(config.parentFile)
            .redirectErrorStream(false)

        // Set environment variables
        processBuilder.environment()["TUN_FD"] = tunFd.toString()

        val process = processBuilder.start()
        Log.d(TAG, "sing-box process started, PID: ${process.toString()}")

        // Log stdout in background
        serviceScope.launch {
            process.inputStream.bufferedReader().forEachLine { line ->
                Log.i(TAG, "[sing-box] $line")
            }
        }

        // Log stderr in background
        serviceScope.launch {
            process.errorStream.bufferedReader().forEachLine { line ->
                Log.w(TAG, "[sing-box:err] $line")
            }
        }

        return process
    }

    /**
     * Monitor sing-box process and handle unexpected exits.
     */
    private suspend fun monitorProcess(process: Process) {
        withContext(Dispatchers.IO) {
            try {
                val exitCode = process.waitFor()
                Log.w(TAG, "sing-box process exited with code: $exitCode")
                if (currentStatus == "connected") {
                    updateStatus("disconnected")
                }
                stopSelf()
            } catch (e: InterruptedException) {
                Log.d(TAG, "Process monitor interrupted")
            }
        }
    }

    private fun stopVpn() {
        Log.d(TAG, "Stopping VPN")
        updateStatus("disconnecting")

        // Kill sing-box process
        singBoxProcess?.let { process ->
            try {
                process.destroy()
                // Give it a moment to shut down gracefully
                serviceScope.launch {
                    delay(1000)
                    if (process.isAlive) {
                        process.destroyForcibly()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping sing-box process", e)
            }
        }
        singBoxProcess = null

        // Close TUN interface
        vpnInterface?.let { pfd ->
            try {
                pfd.close()
            } catch (e: Exception) {
                Log.e(TAG, "Error closing TUN interface", e)
            }
        }
        vpnInterface = null

        // Cleanup config file
        configFile?.delete()
        configFile = null

        updateStatus("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        serviceScope.cancel()
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        // Called when the user revokes VPN permission
        Log.w(TAG, "VPN permission revoked by user")
        stopVpn()
        super.onRevoke()
    }

    /**
     * Update VPN status and broadcast to Flutter layer.
     */
    private fun updateStatus(status: String) {
        currentStatus = status
        val intent = Intent(VpnBridge.ACTION_VPN_STATUS_CHANGED).apply {
            setPackage(packageName)
            putExtra(VpnBridge.EXTRA_VPN_STATUS, status)
        }
        sendBroadcast(intent)
        Log.d(TAG, "VPN status updated: $status")
    }

    // ==================== Notification ====================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Red Star VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN connection status"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(statusText: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Red Star VPN")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
