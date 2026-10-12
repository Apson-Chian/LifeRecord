package ltd.apsonchian.liferecord.service

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.*
import ltd.apsonchian.liferecord.*
import ltd.apsonchian.liferecord.data.*
import java.time.*
import java.util.concurrent.TimeUnit

class ReminderWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val app = applicationContext as LifeRecordApplication
        if(app.store.get("reminder.enabled") != "yes") return Result.success()
        val today = LocalDate.now()
        val records = app.store.load().records.filter { !it.demo && it.date.day() == today }
        val missing = buildList {
            if(app.store.get("reminder.meal", "yes") == "yes" && records.none { it.type == RecordType.MEAL }) add("餐食")
            if(app.store.get("reminder.body", "yes") == "yes" && records.none { it.type == RecordType.BODY }) add("身体测量")
            if(app.store.get("reminder.workout", "no") == "yes" && records.none { it.type == RecordType.WORKOUT } && today.dayOfWeek.value.toString() in app.store.get("reminder.days", "1,3,5").split(',')) add("训练")
        }
        val manager = app.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("record-reminders", "漏记提醒", NotificationManager.IMPORTANCE_DEFAULT))
        if(missing.isNotEmpty() && app.store.get("reminder.lastDay") != today.toString() && (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)) {
            val intent = PendingIntent.getActivity(app, 1, Intent(app, MainActivity::class.java).putExtra("today", true), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            manager.notify(1, NotificationCompat.Builder(app, "record-reminders").setSmallIcon(ltd.apsonchian.liferecord.R.drawable.ic_launcher_foreground).setContentTitle("今天还差一点记录").setContentText("待记录：${missing.joinToString("、")}").setContentIntent(intent).setAutoCancel(true).build())
            app.store.set("reminder.lastDay", today.toString())
        }
        schedule(app, tomorrow = true); return Result.success()
    }
    companion object {
        fun schedule(context: Context, tomorrow: Boolean = false) {
            val app = context.applicationContext as LifeRecordApplication
            val work = WorkManager.getInstance(app)
            if(app.store.get("reminder.enabled") != "yes") { work.cancelUniqueWork("daily-record-reminder"); return }
            val time = runCatching { LocalTime.parse(app.store.get("reminder.time", "20:30")) }.getOrDefault(LocalTime.of(20,30))
            val now = ZonedDateTime.now(); var target = now.toLocalDate().atTime(time).atZone(now.zone)
            if(tomorrow || target <= now) target = target.plusDays(1)
            work.enqueueUniqueWork("daily-record-reminder", ExistingWorkPolicy.REPLACE, OneTimeWorkRequestBuilder<ReminderWorker>().setInitialDelay(Duration.between(now, target).toMillis(), TimeUnit.MILLISECONDS).build())
        }
    }
}
