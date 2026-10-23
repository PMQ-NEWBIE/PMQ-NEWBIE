package vn.wuan.can_lo

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "can_lo/native"
    private val reqSave = 501
    private var pendingContent: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setReminder" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val hour = call.argument<Int>("hour") ?: 7
                        val minute = call.argument<Int>("minute") ?: 0
                        val days = call.argument<Int>("days") ?: 0x7F
                        Reminder.save(this, enabled, hour, minute, days)
                        if (enabled) Reminder.schedule(this) else Reminder.cancel(this)
                        result.success(true)
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 77)
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    }
                    "configureBackground" -> {
                        ScaleService.configure(
                            this,
                            call.argument<Boolean>("enabled") ?: false,
                            call.argument<String>("devices") ?: "[]",
                            call.argument<Boolean>("lb") ?: false,
                        )
                        result.success(true)
                    }
                    "setAppForeground" -> {
                        ScaleService.appForeground = call.argument<Boolean>("value") ?: false
                        result.success(true)
                    }
                    "drainBackground" -> result.success(ScaleService.drain(this))
                    "backgroundStatus" -> result.success(
                        mapOf(
                            "running" to ScaleService.running,
                            "batteryUnrestricted" to batteryUnrestricted(),
                            "error" to ScaleService.lastError,
                        )
                    )
                    "requestBatteryUnrestricted" -> {
                        try {
                            @SuppressLint("BatteryLife")
                            val i = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(i)
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(true)
                    }
                    "saveFile" -> {
                        if (pendingResult != null) {
                            result.error("BUSY", "Đang lưu file khác", null)
                            return@setMethodCallHandler
                        }
                        pendingContent = call.argument<String>("content") ?: ""
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "text/csv"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "can-lo.csv")
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, reqSave)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun batteryUnrestricted(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqSave) return
        val res = pendingResult ?: return
        val content = pendingContent ?: ""
        pendingResult = null
        pendingContent = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            res.success(false)
            return
        }
        try {
            contentResolver.openOutputStream(uri)?.use { it.write(content.toByteArray(Charsets.UTF_8)) }
            res.success(true)
        } catch (e: Exception) {
            res.error("WRITE", e.message, null)
        }
    }
}
