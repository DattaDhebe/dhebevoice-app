package com.textreader.voiceapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.textreader.voiceapp/system"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensurePlaybackChannel" -> {
                    val channelId = call.argument<String>("id")
                    val channelName = call.argument<String>("name")
                    val channelDescription = call.argument<String>("description")

                    if (channelId.isNullOrBlank() || channelName.isNullOrBlank()) {
                        result.error(
                            "invalid_args",
                            "Playback channel id and name are required.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    ensurePlaybackChannel(
                        channelId = channelId,
                        channelName = channelName,
                        channelDescription = channelDescription
                    )
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun ensurePlaybackChannel(
        channelId: String,
        channelName: String,
        channelDescription: String?
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
            ?: return

        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = channelDescription.orEmpty()
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        notificationManager.createNotificationChannel(channel)
    }
}
