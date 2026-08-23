package com.example.lumino_app_moviestreaming

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val CHANNEL = "apk_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            if (call.method == "installApk") {
                val path = call.argument<String>("path")

                if (path == null) {
                    result.error("NO_PATH", "APK path is null", null)
                    return@setMethodCallHandler
                }

                try {
                    val file = File(path)

                    val uri: Uri = FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.provider",
                        file
                    )

                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(
                            uri,
                            "application/vnd.android.package-archive"
                        )
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_GRANT_READ_URI_PERMISSION
                    }

                    startActivity(intent)
                    result.success(null)

                } catch (e: Exception) {
                    result.error("INSTALL_FAILED", e.message, null)
                }

            } else {
                result.notImplemented()
            }
        }
    }
}
