package com.shadow.vortex

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vortex/media").setMethodCallHandler { call, result ->
            if (call.method == "askForNotifications") {
                askForNotifications()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    // Android 13 and newer keep notifications off until the app asks. Android only
    // ever shows this prompt when it's allowed to, so asking again is harmless.
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 71)
    }
}
