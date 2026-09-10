// Keeps local runtime work visible and alive while app sits in background.

package com.syntac

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class RuntimeForegroundService : Service() {
    private lateinit var supervisor: RuntimeJobSupervisor

    override fun onCreate() {
        super.onCreate()
        supervisor = RuntimeJobSupervisor.get(applicationContext)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Runtime tasks",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        startForeground(notificationId, notification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            actionStop -> {
                supervisor.stopAll()
                stopSelf()
                return START_NOT_STICKY
            }
            actionStart -> getSystemService(NotificationManager::class.java)?.notify(notificationId, notification())
        }
        return if (supervisor.hasActiveJobs()) START_STICKY else START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun notification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            openRequestCode,
            Intent(this, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            pendingIntentFlags,
        )
        val stopIntent = PendingIntent.getService(
            this,
            stopRequestCode,
            Intent(this, RuntimeForegroundService::class.java).setAction(actionStop),
            pendingIntentFlags,
        )
        val active = supervisor.hasActiveJobs()
        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Syntac runtime active")
            .setContentText(if (active) "Persistent local jobs are running" else "A local runtime task is running")
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(NotificationCompat.Action.Builder(R.mipmap.ic_launcher, "Stop jobs", stopIntent).build())
            .build()
    }

    companion object {
        const val actionStart = "com.syntac.action.RUNTIME_START"
        const val actionStop = "com.syntac.action.RUNTIME_STOP"
        private const val channelId = "syntac_runtime"
        private const val notificationId = 4101
        private const val openRequestCode = 4102
        private const val stopRequestCode = 4103
        private val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    }
}
