import 'package:flutter/services.dart';

const _channel = MethodChannel('background_updater');

Future<void> start(String apkUrl) async {
  await _channel.invokeMethod('startUpdate', {'apkUrl': apkUrl});
}


