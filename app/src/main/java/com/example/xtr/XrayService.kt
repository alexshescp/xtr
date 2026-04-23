package com.example.xtr

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class XrayService : VpnService() {

    private var process: Process? = null
    private var tunInterface: ParcelFileDescriptor? = null
    private val NOTIFICATION_ID = 1
    private val CHANNEL_ID = "xray_channel"
    
    private var configList: List<String> = emptyList()
    private var currentConfigIndex = 0

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "START" -> {
                if (process == null) {
                    currentConfigIndex = 0
                    startXray()
                }
            }
            "STOP" -> stopXray()
            "NEXT" -> {
                stopXrayProcessOnly()
                currentConfigIndex++
                startXray()
            }
        }
        return START_NOT_STICKY
    }

    private fun loadConfigs() {
        configList = assets.list("")?.filter { it.endsWith(".yaml") || it.endsWith(".yml") }?.sorted() ?: emptyList()
        Log.d("XRAY", "Found configs: $configList")
    }

    private fun startXray() {
        if (configList.isEmpty()) loadConfigs()
        if (configList.isEmpty()) {
            Log.e("XRAY", "No configs found in assets")
            return
        }

        val configName = configList[currentConfigIndex % configList.size]
        Log.d("XRAY", "Starting with config: $configName")

        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, createNotification(configName), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, createNotification(configName))
        }

        try {
            val yamlConfig = assets.open(configName).bufferedReader().use { it.readText() }
            val xrayJson = generateXrayJson(yamlConfig)
            val confFile = File(filesDir, "config.json")
            confFile.writeText(xrayJson)
            
            val binaryFile = File(applicationInfo.nativeLibraryDir, "libxray.so")
            process = ProcessBuilder(binaryFile.absolutePath, "-c", confFile.absolutePath)
                .directory(filesDir)
                .redirectErrorStream(true)
                .start()

            if (tunInterface == null) {
                val builder = Builder()
                    .setSession("xTR")
                    .addAddress("172.19.0.1", 30)
                    .addRoute("0.0.0.0", 0)
                    .addDnsServer("1.1.1.1")
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    builder.setHttpProxy(ProxyInfo.buildDirectProxy("127.0.0.1", 10809))
                }

                try {
                    builder.addDisallowedApplication(packageName)
                } catch (e: Exception) {}

                tunInterface = builder.establish()
            }

            Thread {
                try {
                    process?.inputStream?.bufferedReader()?.use { reader ->
                        while (true) {
                            val line = reader.readLine() ?: break
                            Log.d("XRAY_OUTPUT", line)
                        }
                    }
                } catch (e: Throwable) {}
            }.start()

        } catch (e: Exception) {
            Log.e("XRAY", "Failed to start: ${e.message}")
            if (currentConfigIndex < configList.size * 2) {
                currentConfigIndex++
                startXray()
            } else {
                stopSelf()
            }
        }
    }

    private fun generateXrayJson(yaml: String): String {
        val uuid = Regex("uuid:\\s*([^\\s]+)").find(yaml)?.groupValues?.get(1) ?: ""
        val server = Regex("server:\\s*([^\\s]+)").find(yaml)?.groupValues?.get(1) ?: ""
        val port = Regex("port:\\s*([^\\s]+)").find(yaml)?.groupValues?.get(1)?.toIntOrNull() ?: 443
        val sni = Regex("servername:\\s*([^\\s]+)").find(yaml)?.groupValues?.get(1) ?: ""
        val flow = Regex("flow:\\s*([^\\s]+)").find(yaml)?.groupValues?.get(1) ?: ""
        val pbk = Regex("public-key:\\s*([^\\s]+)").find(yaml)?.groupValues?.get(1) ?: ""
        val sid = Regex("short-id:\\s*([^\\s]+)").find(yaml)?.groupValues?.get(1) ?: ""

        val json = JSONObject()
        json.put("log", JSONObject().put("loglevel", "warning"))

        val inbounds = JSONArray()
        inbounds.put(JSONObject().apply {
            put("protocol", "socks")
            put("port", 10808)
            put("listen", "127.0.0.1")
            put("settings", JSONObject().put("udp", true))
        })
        inbounds.put(JSONObject().apply {
            put("protocol", "http")
            put("port", 10809)
            put("listen", "127.0.0.1")
        })
        json.put("inbounds", inbounds)

        val outbounds = JSONArray()
        outbounds.put(JSONObject().apply {
            put("protocol", "vless")
            put("tag", "proxy")
            put("settings", JSONObject().apply {
                val vnext = JSONArray()
                vnext.put(JSONObject().apply {
                    put("address", server)
                    put("port", port)
                    val users = JSONArray().put(JSONObject().apply {
                        put("id", uuid)
                        put("encryption", "none")
                        put("flow", flow)
                    })
                    put("users", users)
                })
                put("vnext", vnext)
            })
            put("streamSettings", JSONObject().apply {
                put("network", "tcp")
                put("security", "reality")
                put("realitySettings", JSONObject().apply {
                    put("serverName", sni)
                    put("fingerprint", "chrome")
                    put("publicKey", pbk)
                    put("shortId", sid)
                })
            })
        })
        json.put("outbounds", outbounds)

        return json.toString(4)
    }

    private fun stopXrayProcessOnly() {
        process?.destroy()
        process = null
    }

    private fun stopXray() {
        stopXrayProcessOnly()
        tunInterface?.close()
        tunInterface = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Xray Service", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun createNotification(serverName: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("xTR Active")
            .setContentText("Server: $serverName")
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setOngoing(true)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)
}
