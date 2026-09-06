// Keeps long local runtime work visible and alive while app sits in background.

package com.syntac

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class RuntimeForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
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

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_NOT_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    private fun notification(): Notification =
        NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Syntac runtime active")
            .setContentText("A local runtime task is running in background")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

    companion object {
        const val actionStart = "com.syntac.action.RUNTIME_START"
        const val actionStop = "com.syntac.action.RUNTIME_STOP"
        private const val channelId = "syntac_runtime"
        private const val notificationId = 4101
    }
}
