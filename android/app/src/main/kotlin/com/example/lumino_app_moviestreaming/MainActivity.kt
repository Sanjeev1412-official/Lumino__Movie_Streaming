package com.example.lumino_app_moviestreaming

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "apk_installer"
    private var isPipEnabled = false

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

            } else if (call.method == "setPipEnabled") {
                val enabled = call.argument<Boolean>("enabled") ?: false
                isPipEnabled = enabled
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    try {
                        val aspectRatio = android.util.Rational(16, 9)
                        val paramsBuilder = android.app.PictureInPictureParams.Builder()
                            .setAspectRatio(aspectRatio)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                            paramsBuilder.setAutoEnterEnabled(enabled)
                        }
                        setPictureInPictureParams(paramsBuilder.build())
                    } catch (e: Exception) {
                        // ignore
                    }
                }
                result.success(true)

            } else if (call.method == "enterPip") {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    try {
                        val aspectRatio = android.util.Rational(16, 9)
                        val paramsBuilder = android.app.PictureInPictureParams.Builder()
                            .setAspectRatio(aspectRatio)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                            paramsBuilder.setAutoEnterEnabled(true)
                        }
                        val success = enterPictureInPictureMode(paramsBuilder.build())
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("PIP_FAILED", e.message, null)
                    }
                } else {
                    result.error("UNSUPPORTED", "Android version does not support PiP", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isPipEnabled && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            try {
                val aspectRatio = android.util.Rational(16, 9)
                val paramsBuilder = android.app.PictureInPictureParams.Builder()
                    .setAspectRatio(aspectRatio)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    paramsBuilder.setAutoEnterEnabled(true)
                }
                enterPictureInPictureMode(paramsBuilder.build())
            } catch (e: Exception) {
                // ignore
            }
        }
    }
}
