package vn.wuan.can_lo

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelUuid
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import kotlin.math.abs

/**
 * Dịch vụ chạy nền: nghe cân bằng bộ lọc địa chỉ MAC (tiết kiệm pin),
 * tự chốt số theo phiên cân rồi xếp vào hàng đợi cho app nhập khi mở.
 */
@SuppressLint("MissingPermission")
class ScaleService : Service() {

    companion object {
        const val PREF = "can_lo_bg"
        private const val CH_ONGOING = "bg_listen"
        private const val CH_RESULT = "bg_result"
        private const val NOTI_ONGOING = 5101
        private const val NOTI_RESULT = 5102
        private const val HOLD_MS = 1500L
        private const val SILENCE_MS = 8000L
        private const val SVC_181D = "0000181d-0000-1000-8000-00805f9b34fb"
        private const val SVC_181B = "0000181b-0000-1000-8000-00805f9b34fb"

        @Volatile var appForeground = false
        @Volatile var running = false
        @Volatile var lastError: String? = null

        fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

        fun isEnabled(ctx: Context) = prefs(ctx).getBoolean("enabled", false)

        fun configure(ctx: Context, enabled: Boolean, devicesJson: String, unitLb: Boolean) {
            prefs(ctx).edit()
                .putBoolean("enabled", enabled)
                .putString("devices", devicesJson)
                .putBoolean("lb", unitLb)
                .apply()
            if (enabled) start(ctx) else ctx.stopService(Intent(ctx, ScaleService::class.java))
        }

        fun start(ctx: Context) {
            val i = Intent(ctx, ScaleService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            } catch (e: Exception) {
                lastError = e.message ?: e.javaClass.simpleName
            }
        }

        @Synchronized
        fun enqueue(ctx: Context, o: JSONObject) {
            val p = prefs(ctx)
            val arr = try { JSONArray(p.getString("queue", "[]")) } catch (e: Exception) { JSONArray() }
            arr.put(o)
            // Giữ tối đa 500 bản ghi chờ, phòng trường hợp lâu không mở app.
            val trimmed = if (arr.length() > 500) {
                val t = JSONArray()
                for (i in arr.length() - 500 until arr.length()) t.put(arr.get(i))
                t
            } else arr
            p.edit().putString("queue", trimmed.toString()).apply()
        }

        @Synchronized
        fun drain(ctx: Context): String {
            val p = prefs(ctx)
            val s = p.getString("queue", "[]") ?: "[]"
            p.edit().putString("queue", "[]").apply()
            return s
        }
    }

    private class Dev(
        val id: String, val name: String, val proto: String,
        val key: String?, val offset: Int, val be: Boolean, val div: Double,
        val advName: String?, // tên cân tự phát, để nhận lại khi cân đổi địa chỉ
    )

    private class Rd(val kg: Double, val stable: Boolean?, val removed: Boolean, val imp: Int?, val raw: ByteArray)

    private class Sess {
        var active = false
        var start = 0L
        var lastPacket = 0L
        var lastKg: Double? = null
        var holdStart = 0L
        var holdPackets = 0
        var bestKg: Double? = null
        var bestHold = 0L
        var committed: Double? = null
        var imp: Int? = null
        var samples = 0
        var minKg: Double? = null
        var maxKg: Double? = null
        var lastRaw: ByteArray? = null
        var bestRaw: ByteArray? = null
        var lastFinal: Double? = null
        var lastFinalAt = 0L

        fun reset() {
            active = false; lastKg = null; holdPackets = 0
            bestKg = null; bestHold = 0L; committed = null; imp = null
            samples = 0; minKg = null; maxKg = null; lastRaw = null; bestRaw = null
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var scanner: BluetoothLeScanner? = null
    private var scanning = false
    private var fast = false
    private var devices: Map<String, Dev> = emptyMap()
    private val sessions = HashMap<String, Sess>()

    private val tick = object : Runnable {
        override fun run() {
            val now = System.currentTimeMillis()
            for ((id, s) in sessions) {
                if (s.active && now - s.lastPacket > SILENCE_MS) endSession(id, s)
            }
            if (fast && sessions.values.none { it.active }) setFast(false)
            handler.postDelayed(this, 1000)
        }
    }

    private val btReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)) {
                BluetoothAdapter.STATE_ON -> startScan()
                BluetoothAdapter.STATE_OFF, BluetoothAdapter.STATE_TURNING_OFF -> {
                    scanning = false
                    scanner = null
                }
            }
        }
    }

    private val callback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) = handle(result)
        override fun onBatchScanResults(results: MutableList<ScanResult>) { results.forEach { handle(it) } }
        override fun onScanFailed(errorCode: Int) {
            lastError = "Quét nền lỗi mã $errorCode"
            scanning = false
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels()
        try {
            val n = ongoing()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTI_ONGOING, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTI_ONGOING, n)
            }
        } catch (e: Exception) {
            lastError = "Không chạy nền được: ${e.message}"
            stopSelf()
            return
        }
        running = true
        lastError = null
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(btReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED), Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(btReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
        }
        handler.postDelayed(tick, 1000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isEnabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        loadDevices()
        stopScan()
        startScan()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        stopScan()
        handler.removeCallbacksAndMessages(null)
        try { unregisterReceiver(btReceiver) } catch (e: Exception) { }
        super.onDestroy()
    }

    // ---------- Cấu hình ----------
    private fun loadDevices() {
        val out = HashMap<String, Dev>()
        try {
            val arr = JSONArray(prefs(this).getString("devices", "[]"))
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val id = o.getString("id").uppercase(Locale.US)
                val proto = o.getString("proto")
                if (proto == "gattStandard") continue // cân kết nối tự giữ lịch sử, mở app là đồng bộ
                if (!BluetoothAdapter.checkBluetoothAddress(id)) continue
                val c = o.optJSONObject("config") ?: JSONObject()
                val fpName = c.optJSONObject("fp")?.optString("name", "")
                out[id] = Dev(
                    id, o.optString("name", "Cân"), proto,
                    if (c.has("key")) c.getString("key") else null,
                    c.optInt("offset", 0), c.optBoolean("be", false), c.optDouble("div", 100.0),
                    if (fpName.isNullOrEmpty()) null else fpName,
                )
            }
        } catch (e: Exception) {
            lastError = "Cấu hình cân lỗi: ${e.message}"
        }
        devices = out
    }

    // ---------- Quét ----------
    private fun startScan() {
        if (scanning || devices.isEmpty()) return
        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bm.adapter ?: return
        if (!adapter.isEnabled) return
        val sc = adapter.bluetoothLeScanner ?: return
        val filters = devices.keys.map { ScanFilter.Builder().setDeviceAddress(it).build() } +
            devices.values.mapNotNull { it.advName }.distinct()
                .map { ScanFilter.Builder().setDeviceName(it).build() }
        val settings = ScanSettings.Builder()
            .setScanMode(if (fast) ScanSettings.SCAN_MODE_LOW_LATENCY else ScanSettings.SCAN_MODE_LOW_POWER)
            .build()
        try {
            sc.startScan(filters, settings, callback)
            scanner = sc
            scanning = true
        } catch (e: Exception) {
            lastError = "Không quét nền được: ${e.message}"
        }
    }

    private fun stopScan() {
        try { scanner?.stopScan(callback) } catch (e: Exception) { }
        scanning = false
    }

    /** Có người đứng lên cân thì quét nhanh để bắt đủ gói, xong lại về chế độ tiết kiệm. */
    private fun setFast(v: Boolean) {
        if (fast == v) return
        fast = v
        stopScan()
        startScan()
    }

    // ---------- Giải mã ----------
    private fun u8(b: ByteArray, i: Int) = b[i].toInt() and 0xFF

    private fun mi1(b: ByteArray): Rd? {
        if (b.size < 3) return null
        val c = u8(b, 0)
        val raw = u8(b, 1) or (u8(b, 2) shl 8)
        val kg = when {
            c and 0x01 != 0 -> raw / 100.0 * 0.45359237
            c and 0x10 != 0 -> raw / 100.0 * 0.5
            else -> raw / 200.0
        }
        return Rd(kg, c and 0x20 != 0, c and 0x80 != 0, null, b)
    }

    private fun mi2(b: ByteArray): Rd? {
        if (b.size < 13) return null
        val c0 = u8(b, 0)
        val c1 = u8(b, 1)
        val raw = u8(b, 11) or (u8(b, 12) shl 8)
        val kg = if (c0 and 0x01 != 0) raw / 100.0 * 0.45359237 else raw / 200.0
        val imp = u8(b, 9) or (u8(b, 10) shl 8)
        val hasImp = c1 and 0x02 != 0 && imp in 1..2999
        return Rd(kg, c1 and 0x20 != 0, c1 and 0x80 != 0, if (hasImp) imp else null, b)
    }

    private fun learned(d: Dev, rec: ScanRecord): Rd? {
        val key = d.key ?: return null
        val b: ByteArray? = when {
            key.startsWith("m:") -> key.substring(2).toIntOrNull()?.let { rec.getManufacturerSpecificData(it) }
                ?: onlyMfr(rec, d.offset + 2)
            key.startsWith("s:") -> try { rec.getServiceData(ParcelUuid.fromString(key.substring(2))) } catch (e: Exception) { null }
            else -> null
        }
        if (b == null || d.offset + 1 >= b.size) return null
        val raw = if (d.be) (u8(b, d.offset) shl 8) or u8(b, d.offset + 1)
        else u8(b, d.offset) or (u8(b, d.offset + 1) shl 8)
        return Rd(raw / d.div, null, false, null, b)
    }

    /** Cân rẻ hay nhét số đo vào mã hãng: lấy luồng manufacturer duy nhất. */
    private fun onlyMfr(rec: ScanRecord, minLen: Int): ByteArray? {
        val sa = rec.manufacturerSpecificData ?: return null
        var found: ByteArray? = null
        for (i in 0 until sa.size()) {
            val v = sa.valueAt(i) ?: continue
            if (v.size < minLen) continue
            if (found != null) return null
            found = v
        }
        return found
    }

    private fun parse(d: Dev, rec: ScanRecord): Rd? = when (d.proto) {
        "miScale1" -> rec.getServiceData(ParcelUuid.fromString(SVC_181D))?.let { mi1(it) }
        "miScale2" -> rec.getServiceData(ParcelUuid.fromString(SVC_181B))?.let { mi2(it) }
        "learned" -> learned(d, rec)
        else -> null
    }

    // ---------- Chốt số theo phiên ----------
    private fun handle(r: ScanResult) {
        val id = r.device?.address?.uppercase(Locale.US) ?: return
        val advName = r.scanRecord?.deviceName
        // Cân đổi địa chỉ thì nhận lại bằng tên nó tự phát.
        val dev = devices[id] ?: devices.values.firstOrNull { it.advName != null && it.advName == advName } ?: return
        if (appForeground) return // app đang mở thì app tự lo, tránh lưu trùng
        val rec = r.scanRecord ?: return
        val rd = parse(dev, rec) ?: return
        handler.post { onReading(dev, rd) }
    }

    private fun onReading(d: Dev, r: Rd) {
        val now = System.currentTimeMillis()
        val s = sessions.getOrPut(d.id) { Sess() }
        s.lastPacket = now
        if (r.removed || r.kg < 2) {
            if (s.active) endSession(d.id, s)
            return
        }
        if (r.kg < 5 || r.kg > 300) return
        if (!s.active) {
            s.reset()
            s.active = true
            s.start = now
            setFast(true)
        }
        s.samples++
        s.minKg = s.minKg?.let { minOf(it, r.kg) } ?: r.kg
        s.maxKg = s.maxKg?.let { maxOf(it, r.kg) } ?: r.kg
        val last = s.lastKg
        if (last == null || abs(r.kg - last) > 0.1) {
            s.lastKg = r.kg
            s.holdStart = now
            s.holdPackets = 1
        } else {
            s.holdPackets++
        }
        s.lastRaw = r.raw
        if (r.imp != null) s.imp = r.imp
        val held = now - s.holdStart
        if (s.bestKg == null || held >= s.bestHold) {
            s.bestHold = held
            s.bestKg = r.kg
            s.bestRaw = r.raw
        }
        val committed = s.committed
        val saved = committed != null && abs(r.kg - committed) <= 0.5
        if (saved) return
        if (r.stable == true) commit(d, s, r.kg, "scaleStable", r.raw)
        else if (held >= HOLD_MS && s.holdPackets >= 2) commit(d, s, r.kg, "hold", r.raw)
    }

    private fun endSession(id: String, s: Sess) {
        val d = devices[id]
        if (d != null && s.active && s.committed == null) {
            val best = s.bestKg
            val last = s.lastKg
            if (best != null && s.bestHold >= 300) commit(d, s, best, "sessionEnd", s.bestRaw)
            else if (last != null && s.lastPacket - s.start >= 2000) commit(d, s, last, "sessionEnd", s.lastRaw)
        }
        s.reset()
    }

    private fun hex(b: ByteArray?): String? =
        b?.joinToString(" ") { String.format(Locale.US, "%02X", it.toInt() and 0xFF) }

    private fun commit(d: Dev, s: Sess, kg: Double, method: String, raw: ByteArray?) {
        val now = System.currentTimeMillis()
        s.committed = kg
        val lf = s.lastFinal
        if (lf != null && abs(kg - lf) < 0.3 && now - s.lastFinalAt < 90_000) return
        s.lastFinal = kg
        s.lastFinalAt = now
        val rounded = Math.round(kg * 100) / 100.0
        val o = JSONObject()
        o.put("deviceId", d.id)
        o.put("kg", rounded)
        o.put("at", now)
        s.imp?.let { o.put("imp", it) }
        o.put("method", method)
        o.put("samples", s.samples)
        o.put("durationMs", now - s.start)
        s.minKg?.let { o.put("minKg", it) }
        s.maxKg?.let { o.put("maxKg", it) }
        hex(raw)?.let { o.put("raw", it) }
        enqueue(this, o)
        notifyResult(d, rounded)
    }

    // ---------- Thông báo ----------
    private fun createChannels() {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(CH_ONGOING, "Nghe cân chạy nền", NotificationManager.IMPORTANCE_MIN))
        nm.createNotificationChannel(NotificationChannel(CH_RESULT, "Kết quả cân", NotificationManager.IMPORTANCE_DEFAULT))
    }

    private fun openApp(req: Int): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(this, req, launch, flags)
    }

    @Suppress("DEPRECATION")
    private fun builder(ch: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, ch) else Notification.Builder(this)

    private fun ongoing(): Notification = builder(CH_ONGOING)
        .setSmallIcon(R.drawable.ic_stat_scale)
        .setContentTitle("Cân Lỏ đang chờ cân")
        .setContentText("Bước lên cân là số tự được ghi lại")
        .setContentIntent(openApp(5201))
        .setOngoing(true)
        .build()

    private fun notifyResult(d: Dev, kg: Double) {
        val lb = prefs(this).getBoolean("lb", false)
        val txt = if (lb) String.format(Locale.US, "%.2f lb", kg / 0.45359237)
        else String.format(Locale.US, "%.2f kg", kg)
        val n = builder(CH_RESULT)
            .setSmallIcon(R.drawable.ic_stat_scale)
            .setContentTitle("Đã ghi $txt")
            .setContentText("Từ ${d.name}. Mở app để xem biểu đồ.")
            .setContentIntent(openApp(5202))
            .setAutoCancel(true)
            .build()
        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTI_RESULT, n)
        } catch (e: SecurityException) { }
    }
}
