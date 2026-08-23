// lib/download_manager.dart
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumino_app_moviestreaming/main.dart';
import 'package:lumino_app_moviestreaming/my_downloads_page.dart';

class DownloadTaskMeta {
  final String title;
  final String quality;
  final double? totalSize;
  final int? tmdbId;
  final String? mediaType;
  final int? season;
  final int? episode;
  final String? posterPath;
  final String? primeboxUrl;

  DownloadTaskMeta({
    required this.title,
    this.quality = '',
    this.totalSize,
    this.tmdbId,
    this.mediaType,
    this.season,
    this.episode,
    this.posterPath,
    this.primeboxUrl,
  });

  factory DownloadTaskMeta.fromMetaData(String? metaData) {
    if (metaData == null || metaData.isEmpty) {
      return DownloadTaskMeta(title: 'Unknown');
    }
    try {
      final decoded = jsonDecode(metaData);
      if (decoded is Map) {
        return DownloadTaskMeta(
          title: decoded['title'] ?? 'Unknown',
          quality: decoded['quality'] ?? '',
          totalSize: decoded['totalSize']?.toDouble(),
          tmdbId: decoded['tmdbId'],
          mediaType: decoded['mediaType'],
          season: decoded['season'],
          episode: decoded['episode'],
          posterPath: decoded['posterPath'],
          primeboxUrl: decoded['primeboxUrl'],
        );
      }
    } catch (_) {
      // Not JSON, assume it's just the title (old format)
      return DownloadTaskMeta(title: metaData);
    }
    return DownloadTaskMeta(title: metaData);
  }
}

class DownloadEntry {
  final DownloadTask task;
  double progress; // 0.0 -> 1.0
  TaskStatus status;
  double? networkSpeed; // in bytes/s
  Duration? timeRemaining;

  DownloadEntry({
    required this.task,
    required this.progress,
    required this.status,
    this.networkSpeed,
    this.timeRemaining,
  });
}

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  bool _initialized = false;

  /// taskId -> DownloadEntry
  final ValueNotifier<Map<String, DownloadEntry>> activeDownloadsNotifier =
      ValueNotifier(<String, DownloadEntry>{});

  /// List of completed tasks metadata
  final ValueNotifier<List<Map<String, dynamic>>> completedDownloadsNotifier =
      ValueNotifier([]);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _loadCompletedDownloads();

    // 1) Configure notifications (Android & iOS only; desktop ignores)
    FileDownloader().configureNotification(
      running: const TaskNotification(
        'Downloading',
        'file: {filename} ({progress})',
      ),
      paused: const TaskNotification('Paused', 'file: {filename}'),
      complete: const TaskNotification('Download finished', 'file: {filename}'),
      error: const TaskNotification('Download failed', 'file: {filename}'),
      progressBar: true,
      tapOpensFile: false, // Don't open file with external player
    );

    // 2) Register callback for notification taps to open Download Page
    FileDownloader().registerCallbacks(
      taskNotificationTapCallback: (task, notificationType) {
        debugPrint('Notification tapped for task: ${task.taskId}');
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => const MyDownloadsPage()),
        );
      },
    );

    // 3) Central listener: handle completion, progress, etc.
    FileDownloader().updates.listen((update) async {
      switch (update) {
        case TaskStatusUpdate():
          final task = update.task;

          // Only care about DownloadTask
          if (task is DownloadTask) {
            // Ignore posters in the HUD and completed list
            if (task.directory == 'downloads/posters') return;

            final taskId = task.taskId;
            final current = Map<String, DownloadEntry>.from(
              activeDownloadsNotifier.value,
            );

            // update or create entry
            final existing = current[taskId];
            final entry =
                existing ??
                DownloadEntry(task: task, progress: 0.0, status: update.status);

            entry.status = update.status;
            current[taskId] = entry;

            // Remove when done / failed / canceled
            if (update.status == TaskStatus.complete ||
                update.status == TaskStatus.failed ||
                update.status == TaskStatus.canceled) {
              current.remove(taskId);
            }

            if (update.status == TaskStatus.complete) {
              // Save to completed downloads list
              await _saveCompletedDownload(task);
            } else if (update.status == TaskStatus.failed) {
              debugPrint(
                'Download FAILED: ${task.filename}, ${update.exception}',
              );
            } else if (update.status == TaskStatus.canceled) {
              debugPrint('Download CANCELED by user: ${task.filename}');
            }

            activeDownloadsNotifier.value = current;
          }
          break;

        case TaskProgressUpdate():
          final task = update.task;
          if (task is! DownloadTask) break;
          if (task.directory == 'downloads/posters') break;

          final taskId = task.taskId;
          final p = update.progress;

          final current = Map<String, DownloadEntry>.from(
            activeDownloadsNotifier.value,
          );
          final existing = current[taskId];

          if (existing != null) {
            existing.progress = p;
            existing.networkSpeed = update.networkSpeed;
            existing.timeRemaining = update.timeRemaining;
            current[taskId] = existing;
          } else {
            // If we missed the initial track, still show
            current[taskId] = DownloadEntry(
              task: task,
              progress: p,
              status: TaskStatus.running,
              networkSpeed: update.networkSpeed,
              timeRemaining: update.timeRemaining,
            );
          }

          activeDownloadsNotifier.value = current;

          debugPrint(
            'Progress ${task.filename} ($taskId): '
            '${(p * 100).toStringAsFixed(1)}%',
          );
          break;
      }
    });

    // 3) Start tracking + background recovery
    await FileDownloader().start();
  }

  /// Process a DASH/MPD download using FFmpeg natively on supported platforms
  Future<bool> processFFmpegDownload(DownloadTask task) async {
    if (!Platform.isWindows) {
      debugPrint('FFmpeg download only supported on Windows');
      return false;
    }
    trackTask(task); // Adds it to active list

    try {
      final outputPath = await task.filePath();

      // Update status to running
      var current = Map<String, DownloadEntry>.from(
        activeDownloadsNotifier.value,
      );
      if (current.containsKey(task.taskId)) {
        current[task.taskId]!.status = TaskStatus.running;
        current[task.taskId]!.progress = -1.0; // indeterminate
        activeDownloadsNotifier.value = current;
      }

      final headerArgs = <String>[];
      if (task.headers.isNotEmpty) {
        final hString =
            task.headers.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('\r\n') +
            '\r\n';
        headerArgs.addAll(['-headers', hString]);
      }

      final process = await Process.start('ffmpeg', [
        ...headerArgs,
        '-i',
        task.url,
        '-c',
        'copy',
        '-y',
        outputPath,
      ]);

      final exitCode = await process.exitCode;

      current = Map<String, DownloadEntry>.from(activeDownloadsNotifier.value);
      if (exitCode == 0) {
        if (current.containsKey(task.taskId)) {
          current.remove(task.taskId);
          activeDownloadsNotifier.value = current;
        }
        await _saveCompletedDownload(task);
      } else {
        if (current.containsKey(task.taskId)) {
          current[task.taskId]!.status = TaskStatus.failed;
          activeDownloadsNotifier.value = current;
        }
      }
      return exitCode == 0;
    } catch (e) {
      debugPrint('FFmpeg download error: $e');
      final current = Map<String, DownloadEntry>.from(
        activeDownloadsNotifier.value,
      );
      if (current.containsKey(task.taskId)) {
        current[task.taskId]!.status = TaskStatus.failed;
        activeDownloadsNotifier.value = current;
      }
      return false;
    }
  }

  /// Call this right after creating a DownloadTask (before enqueue)
  void trackTask(DownloadTask task) {
    final current = Map<String, DownloadEntry>.from(
      activeDownloadsNotifier.value,
    );
    current[task.taskId] = DownloadEntry(
      task: task,
      progress: 0.0,
      status: TaskStatus.enqueued,
    );
    activeDownloadsNotifier.value = current;
  }

  /// Cancel a specific task by id
  Future<void> cancelTask(String taskId) async {
    try {
      await FileDownloader().cancelTasksWithIds([taskId]);
    } catch (e) {
      debugPrint('cancelTask failed for $taskId: $e');
    }
  }

  // ---------- Persistence ----------

  Future<void> _loadCompletedDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('completed_downloads');
    if (data != null) {
      completedDownloadsNotifier.value = List<Map<String, dynamic>>.from(
        json.decode(data),
      );
    }
  }

  Future<void> _saveCompletedDownload(DownloadTask task) async {
    final prefs = await SharedPreferences.getInstance();
    final current = List<Map<String, dynamic>>.from(
      completedDownloadsNotifier.value,
    );

    // Check if already exists
    if (current.any((e) => e['taskId'] == task.taskId)) return;

    final filePath = await task.filePath();

    final meta = DownloadTaskMeta.fromMetaData(task.metaData);

    current.insert(0, {
      'taskId': task.taskId,
      'title': meta.title,
      'quality': meta.quality,
      'filename': task.filename,
      'path': filePath,
      'date': DateTime.now().toIso8601String(),
      'totalSize': meta.totalSize,
      'tmdbId': meta.tmdbId,
      'mediaType': meta.mediaType,
      'season': meta.season,
      'episode': meta.episode,
      'posterPath': meta.posterPath,
      'primeboxUrl': meta.primeboxUrl,
    });

    completedDownloadsNotifier.value = current;
    await prefs.setString('completed_downloads', json.encode(current));
  }

  Future<void> deleteCompletedDownload(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = List<Map<String, dynamic>>.from(
      completedDownloadsNotifier.value,
    );

    final index = current.indexWhere((e) => e['taskId'] == taskId);
    if (index != -1) {
      final item = current[index];
      final file = File(item['path']);
      if (await file.exists()) {
        await file.delete();
      }
      current.removeAt(index);
      completedDownloadsNotifier.value = current;
      await prefs.setString('completed_downloads', json.encode(current));
    }
  }

  /// Convenience: ask OS for notification permission if needed
  Future<void> ensureNotificationPermission() async {
    const permissionType = PermissionType.notifications;
    var status = await FileDownloader().permissions.status(permissionType);
    if (status != PermissionStatus.granted) {
      status = await FileDownloader().permissions.request(permissionType);
      debugPrint('Notification permission: $status');
    }
  }
}
