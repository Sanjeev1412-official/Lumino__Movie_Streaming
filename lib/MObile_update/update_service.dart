import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const String updateUrl =
      'https://sanjeevsnair.github.io/Lumino_window_Autoupdater/updates/update.json';

  /// STEP 1 — ONLY check update (NO download)
  static Future<Map<String, dynamic>?> checkUpdateOnly() async {
    final res = await http.get(Uri.parse(updateUrl));
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);

    final info = await PackageInfo.fromPlatform();
    final currentCode = int.parse(info.buildNumber);
    final latestCode = data['versionCode'];

    if (latestCode <= currentCode) {
      return null;
    }

    return {
      'versionCode': latestCode,
      'versionName': data['versionName'],
      'apkUrl': data['apkUrl'],
      'changelog': data['changelog'],
    };
  }

  /// STEP 2 — Download APK WITH progress
  static Future<String> downloadApkWithProgress({
    required String apkUrl,
    required void Function(double progress) onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(apkUrl));
    final response = await request.send();

    final totalBytes = response.contentLength;
    if (totalBytes == null || totalBytes <= 0) {
      throw Exception('Invalid APK size');
    }

    int receivedBytes = 0;

    final dir = await getExternalStorageDirectory();
    final filePath = '${dir!.path}/lumino_update.apk';
    final file = File(filePath);
    final sink = file.openWrite();

    await response.stream.listen(
      (chunk) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        onProgress(receivedBytes / totalBytes);
      },
      onError: (e) async {
        await sink.close();
        throw e;
      },
      onDone: () async {
        await sink.close();
      },
      cancelOnError: true,
    ).asFuture();

    return filePath;
  }
}
