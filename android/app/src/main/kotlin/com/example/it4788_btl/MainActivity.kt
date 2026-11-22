package com.example.it4788_btl

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import android.content.Intent
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sqb.notification_sounds")
            .setMethodCallHandler { call, result ->
                if (call.method != "uri") {
                    result.notImplemented()
                } else {
                    try {
                        val path = call.argument<String>("path") ?: throw IllegalArgumentException()
                        val file = File(path).canonicalFile
                        val root = File(filesDir, "notification-sounds").canonicalPath + File.separator
                        require(file.path.startsWith(root) && file.isFile)
                        val uri = FileProvider.getUriForFile(this, "$packageName.notification_sounds", file)
                        grantUriPermission("com.android.systemui", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        result.success(uri.toString())
                    } catch (_: Exception) {
                        result.error("SOUND_FILE", "Không thể dùng tệp âm thanh này.", null)
                    }
                }
            }
    }
}
