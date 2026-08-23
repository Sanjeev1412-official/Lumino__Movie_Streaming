import 'package:flutter/services.dart';

class ApkInstaller {
  static const MethodChannel _channel =
      MethodChannel('apk_installer');

  static Future<void> install(String path) async {
    await _channel.invokeMethod(
      'installApk',
      {'path': path},
    );
  }
}
