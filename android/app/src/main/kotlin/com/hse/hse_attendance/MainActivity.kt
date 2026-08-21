package com.hse.hse_attendance

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hse.hse_attendance/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val source = File(call.argument<String>("path") ?: error("缺少文件路径"))
                    val shareDir = File(cacheDir, "shared_exports").apply { mkdirs() }
                    val sharedFile = File(shareDir, source.name)
                    source.copyTo(sharedFile, overwrite = true)
                    val uri = FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        sharedFile,
                    )
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(intent, "分享检查表"))
                    result.success(null)
                } catch (error: Exception) {
                    result.error("SHARE_FAILED", error.message, null)
                }
            }
    }
}
