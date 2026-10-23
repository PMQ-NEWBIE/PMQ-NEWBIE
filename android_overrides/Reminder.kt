package vn.wuan.can_lo

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

object Reminder {
    private const val PREF = "can_lo_reminder"
    private const val CHANNEL = "weigh_reminder"

    fun save(ctx: Context, enabled: Boolean, hour: Int, minute: Int, days: Int) {
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit()
            .putBoolean("enabled", enabled)
            .putInt("hour", hour)
            .putInt("minute", minute)
            .putInt("days", days)
            .apply()
    }

    private fun pending(ctx: Context): PendingIntent {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(ctx, 4201, Intent(ctx, ReminderReceiver::class.java), flags)
    }

    fun schedule(ctx: Context) {
        val p = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (!p.getBoolean("enabled", false)) {
            cancel(ctx)
            return
        }
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, p.getInt("hour", 7))
            set(Calendar.MINUTE, p.getInt("minute", 0))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setWindow(AlarmManager.RTC_WAKEUP, cal.timeInMillis, 10 * 60 * 1000L, pending(ctx))
    }

    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(ctx))
    }

    fun shouldFireToday(ctx: Context): Boolean {
        val p = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (!p.getBoolean("enabled", false)) return false
        val dow = Calendar.getInstance().get(Calendar.DAY_OF_WEEK) // 1 = CN, 2 = T2
        val idx = (dow + 5) % 7 // T2 = 0 ... CN = 6
        return (p.getInt("days", 0x7F) and (1 shl idx)) != 0
    }

    fun notify(ctx: Context) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Nhắc cân", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) flags = flags or PendingIntent.FLAG_IMMUTABLE
        val content = PendingIntent.getActivity(ctx, 4202, launch, flags)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        val n = builder
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle("Tới giờ cân rồi")
            .setContentText("Bước lên cân rồi mở Cân Lỏ để lưu số hôm nay.")
            .setContentIntent(content)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(4203, n)
        } catch (e: SecurityException) {
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (Reminder.shouldFireToday(ctx)) Reminder.notify(ctx)
        Reminder.schedule(ctx)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val a = intent.action ?: return
        if (a == Intent.ACTION_BOOT_COMPLETED || a == Intent.ACTION_MY_PACKAGE_REPLACED) {
            Reminder.schedule(ctx)
            if (ScaleService.isEnabled(ctx)) ScaleService.start(ctx)
        }
    }
}
