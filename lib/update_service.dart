// lib/update_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:app_updater/app_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─── GitHub repo config ────────────────────────────────────────────────────────
const _githubOwner = 'Sanjeevsnair';
const _githubRepo = 'Lumino_window_Autoupdater';
// Must match android:authorities in AndroidManifest.xml
const _fileProviderAuthority = 'com.example.lumino_app_moviestreaming.provider';

// ─── Design tokens (matches Lumino dark theme) ────────────────────────────────
class _C {
  static const bg = Color(0xFF0C0D12);
  static const surface = Color(0xFF161720);
  static const border = Color(0xFF222333);
  static const error = Color(0xFFC0392B);
}

// ─── Notification tap handler (top-level for background isolates) ─────────────
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  if (response.actionId == 'cancel_update') {
    final port = IsolateNameServer.lookupPortByName('lumino_update_port');
    port?.send('cancel');
  }
}

// ─── Active Download state holder ─────────────────────────────────────────────
class ActiveDownload {
  final String newVersion;
  final String downloadUrl;

  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<int> received = ValueNotifier(0);
  final ValueNotifier<int> total = ValueNotifier(0);
  final ValueNotifier<String> status = ValueNotifier('Connecting...');

  bool isFailed = false;
  bool isInstalling = false;
  bool isCancelled = false;

  http.Client? client;

  ActiveDownload({required this.newVersion, required this.downloadUrl});
}

// ─── Singleton UpdateService ───────────────────────────────────────────────────
class UpdateService {
  UpdateService._();
  static final UpdateService _instance = UpdateService._();
  factory UpdateService() => _instance;

  late final AppUpdater _appUpdater;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _notificationsInitialized = false;

  ActiveDownload? _activeDownload;
  ActiveDownload? get activeDownload => _activeDownload;

  // ── Init ────────────────────────────────────────────────────────────────────
  void _init() {
    if (_initialized) return;
    _initialized = true;

    // Register isolate port so background notification cancel works
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping('lumino_update_port');
    IsolateNameServer.registerPortWithName(port.sendPort, 'lumino_update_port');
    port.listen((msg) {
      if (msg == 'cancel') cancelActiveDownload();
    });

    _appUpdater = AppUpdater.configure(
      githubOwner: _githubOwner,
      githubRepo: _githubRepo,
      githubIncludePrereleases: false,
      checkFrequency: const Duration(hours: 24),
    );
  }

  // ── Notification init (Android only) ────────────────────────────────────────
  Future<void> _initNotifications() async {
    if (_notificationsInitialized || !Platform.isAndroid) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
    );
    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (r) {
        if (r.actionId == 'cancel_update') {
          cancelActiveDownload();
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    try {
      final plugin = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await plugin?.requestNotificationsPermission();
    } catch (_) {}

    _notificationsInitialized = true;
  }

  // ── Silent check on startup ──────────────────────────────────────────────────
  Future<void> checkForUpdates(BuildContext context) async {
    if (kIsWeb) return;
    try {
      _init();
      final info = await _appUpdater.checkForUpdate(respectFrequency: false);
      if (!info.updateAvailable) return;
      if (!context.mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final skipped = prefs.getString('lumino_update_skipped');
      if (skipped != null && skipped == info.latestVersion) return;
      final doNotAsk = prefs.getBool('lumino_update_do_not_ask') ?? false;
      if (doNotAsk) return;

      final assetUrl = await _getAssetUrl(info.latestVersion);
      if (assetUrl == null) return;
      if (!context.mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        builder: (_) => _LuminoUpdateDialog(
          currentVersion: info.currentVersion,
          newVersion: info.latestVersion ?? 'New',
          releaseNotes: info.releaseNotes,
          assetUrl: assetUrl,
          onUpdate: (url) =>
              _beginInAppUpdate(context, url, info.latestVersion ?? ''),
          onSkipVersion: () async {
            if (info.latestVersion != null) {
              await prefs.setString(
                  'lumino_update_skipped', info.latestVersion!);
            }
          },
          onDoNotAsk: () async {
            await prefs.setBool('lumino_update_do_not_ask', true);
          },
        ),
      );
    } catch (e) {
      debugPrint('[UpdateService] checkForUpdates failed: $e');
    }
  }

  // ── Manual check (from "Update Center" page) ─────────────────────────────────
  Future<void> checkForUpdatesNow(BuildContext context) async {
    if (kIsWeb) return;
    try {
      _init();
      final info = await _appUpdater.checkForUpdate(respectFrequency: false);
      if (!context.mounted) return;

      if (info.updateAvailable) {
        final assetUrl = await _getAssetUrl(info.latestVersion);
        if (!context.mounted) return;
        await showDialog(
          context: context,
          barrierColor: Colors.black54,
          builder: (_) => _LuminoUpdateDialog(
            currentVersion: info.currentVersion,
            newVersion: info.latestVersion ?? 'New',
            releaseNotes: info.releaseNotes,
            assetUrl: assetUrl,
            onUpdate: (url) =>
                _beginInAppUpdate(context, url, info.latestVersion ?? ''),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lumino is already up to date!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] checkForUpdatesNow failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not check for updates. Try again later.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Fetch correct asset URL from GitHub release ──────────────────────────────
  Future<String?> _getAssetUrl(String? version) async {
    try {
      final apiUrl = version != null
          ? 'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/tags/$version'
          : 'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest';

      final res = await http.get(
        Uri.parse(apiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final assets = (data['assets'] as List<dynamic>?) ?? [];

      final ext = Platform.isAndroid
          ? '.apk'
          : (Platform.isWindows ? '.exe' : null);
      if (ext == null) return null;

      for (final a in assets) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        if (name.endsWith(ext)) {
          return a['browser_download_url'] as String?;
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] _getAssetUrl failed: $e');
    }
    return null;
  }

  // ── Start in-app download + install flow ─────────────────────────────────────
  Future<void> _beginInAppUpdate(
      BuildContext context, String? assetUrl, String newVersion) async {
    if (assetUrl == null) {
      // Fallback: open GitHub releases page
      await _appUpdater.openStore();
      return;
    }

    if (_activeDownload != null &&
        !_activeDownload!.isFailed &&
        !_activeDownload!.isCancelled) {
      _showProgressDialog(context);
      return;
    }

    _activeDownload = ActiveDownload(
        newVersion: newVersion, downloadUrl: assetUrl);
    _startBackgroundDownload();
    _showProgressDialog(context);
  }

  void _showProgressDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => _DownloadProgressDialog(
        activeDownload: _activeDownload!,
        onRetry: () {
          _activeDownload = ActiveDownload(
            newVersion: _activeDownload!.newVersion,
            downloadUrl: _activeDownload!.downloadUrl,
          );
          _startBackgroundDownload();
          Navigator.pop(context);
          _showProgressDialog(context);
        },
        onCancel: () {
          cancelActiveDownload();
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── Cancel ────────────────────────────────────────────────────────────────────
  void cancelActiveDownload() {
    if (_activeDownload != null) {
      _activeDownload!.isCancelled = true;
      _activeDownload!.client?.close();
      _activeDownload = null;
      if (_notificationsInitialized) {
        try {
          _notifications.cancel(id: 987);
        } catch (_) {}
      }
    }
  }

  // ── Android progress notification ─────────────────────────────────────────────
  Future<void> _updateNotification(
      int max, int progress, String body) async {
    if (!Platform.isAndroid) return;
    if (_activeDownload == null ||
        _activeDownload!.isInstalling ||
        _activeDownload!.isFailed ||
        _activeDownload!.isCancelled) return;

    await _initNotifications();
    final details = AndroidNotificationDetails(
      'lumino_updates',
      'App Updates',
      channelDescription: 'Downloading Lumino app updates',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: max,
      progress: progress,
      indeterminate: max == 0,
      ongoing: true,
      onlyAlertOnce: true,
      actions: const [
        AndroidNotificationAction(
          'cancel_update',
          'Cancel',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    if (_activeDownload == null || _activeDownload!.isCancelled) return;
    await _notifications.show(
      id: 987,
      title: 'Downloading Lumino v${_activeDownload?.newVersion}',
      body: body,
      notificationDetails: NotificationDetails(android: details),
    );
  }

  Future<void> _showFinishedNotification(bool success) async {
    if (!Platform.isAndroid) return;
    await _initNotifications();
    await _notifications.cancel(id: 987);
    if (!success) {
      const details = AndroidNotificationDetails(
        'lumino_updates', 'App Updates',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      await _notifications.show(
        id: 986,
        title: 'Update Failed',
        body: 'Could not download the update.',
        notificationDetails: const NotificationDetails(android: details),
      );
    }
  }

  // ── HTTP streaming download ───────────────────────────────────────────────────
  Future<void> _startBackgroundDownload() async {
    final download = _activeDownload!;
    try {
      final tmpDir = await getTemporaryDirectory();
      final ext = Platform.isAndroid ? '.apk' : '.exe';
      final savePath = '${tmpDir.path}/Lumino-${download.newVersion}$ext';

      download.client = http.Client();
      final req = http.Request('GET', Uri.parse(download.downloadUrl));
      final res = await download.client!.send(req);

      final total = res.contentLength ?? 0;
      int received = 0;

      download.total.value = total;
      download.status.value = 'Downloading...';

      final file = File(savePath);
      final sink = file.openWrite();

      Timer? notifTimer;
      if (Platform.isAndroid) {
        notifTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!download.isCancelled && !download.isFailed) {
            _updateNotification(
              total,
              received,
              '${(received / (1024 * 1024)).toStringAsFixed(1)} MB'
              ' / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB',
            );
          }
        });
      }

      await for (final chunk in res.stream) {
        if (download.isCancelled) {
          await sink.close();
          notifTimer?.cancel();
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        download.received.value = received;
        download.progress.value = total > 0 ? received / total : 0;
      }

      await sink.flush();
      await sink.close();
      notifTimer?.cancel();

      if (download.isCancelled) return;

      download.isInstalling = true;
      download.status.value = 'Installing...';
      download.progress.value = 1.0;

      await _showFinishedNotification(true);
      await _installUpdate(savePath);
    } catch (e) {
      if (download.isCancelled) return;
      debugPrint('[UpdateService] Download error: $e');
      download.isFailed = true;
      download.status.value = 'Download failed';
      await _showFinishedNotification(false);
    }
  }

  // ── Platform install ──────────────────────────────────────────────────────────
  Future<void> _installUpdate(String filePath) async {
    if (Platform.isAndroid) {
      final fileName = filePath.split('/').last;
      final contentUri = 'content://$_fileProviderAuthority/cache/$fileName';
      final intent = AndroidIntent(
        action: 'action_view',
        data: contentUri,
        type: 'application/vnd.android.package-archive',
        flags: [0x00000001, 0x10000000],
      );
      await intent.launch();
    } else if (Platform.isWindows) {
      await Process.start(filePath, [],
          mode: ProcessStartMode.detached, runInShell: false);
      await Future.delayed(const Duration(seconds: 1));
      exit(0);
    }
  }

  void dispose() {
    if (_initialized) {
      _appUpdater.dispose();
      _initialized = false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ─── Update Available Dialog ───────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

class _LuminoUpdateDialog extends StatelessWidget {
  final String currentVersion;
  final String newVersion;
  final String? releaseNotes;
  final String? assetUrl;
  final void Function(String? url) onUpdate;
  final VoidCallback? onSkipVersion;
  final VoidCallback? onDoNotAsk;

  const _LuminoUpdateDialog({
    required this.currentVersion,
    required this.newVersion,
    required this.onUpdate,
    this.releaseNotes,
    this.assetUrl,
    this.onSkipVersion,
    this.onDoNotAsk,
  });

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            color: _C.bg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _C.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 20))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Orange accent bar + header
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orangeAccent.withValues(alpha: 0.15),
                      Colors.transparent
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26)),
                  border: Border(
                      bottom: BorderSide(color: _C.border, width: 1)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.system_update_rounded,
                          color: Colors.orangeAccent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Update Available',
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16),
                          ),
                          Text(
                            'A new version of Lumino is ready',
                            style: GoogleFonts.outfit(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Version pill
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _C.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _C.border, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _VersionChip(
                          label: 'CURRENT',
                          version: 'v$currentVersion',
                          muted: true),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Icon(Icons.arrow_forward_rounded,
                            size: 16, color: Colors.white24),
                      ),
                      _VersionChip(
                          label: 'NEW',
                          version: 'v$newVersion',
                          muted: false),
                    ],
                  ),
                ),
              ),

              // Release notes
              if (releaseNotes != null && releaseNotes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("WHAT'S NEW",
                          style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white38,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 110),
                        child: SingleChildScrollView(
                          child: Text(releaseNotes!,
                              style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  height: 1.5)),
                        ),
                      ),
                    ],
                  ),
                ),

              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Download & Install button
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        onUpdate(assetUrl);
                      },
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF9800),
                              Color(0xFFFF6D00)
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.download_rounded,
                                color: Colors.black, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              assetUrl != null
                                  ? 'Download & Install'
                                  : 'View on GitHub',
                              style: GoogleFonts.outfit(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _TextAction(
                            label: 'Later',
                            onTap: () => Navigator.of(context).pop()),
                        Container(
                            width: 1,
                            height: 16,
                            color: _C.border),
                        _TextAction(
                          label: 'Skip version',
                          onTap: () {
                            Navigator.of(context).pop();
                            onSkipVersion?.call();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ─── Download Progress Dialog ──────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

class _DownloadProgressDialog extends StatelessWidget {
  final ActiveDownload activeDownload;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _DownloadProgressDialog({
    required this.activeDownload,
    required this.onRetry,
    required this.onCancel,
  });

  String _fmt(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: _C.bg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _C.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 20))
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ValueListenableBuilder<double>(
              valueListenable: activeDownload.progress,
              builder: (context, progress, _) {
                final isInstalling = activeDownload.isInstalling;
                final isFailed = activeDownload.isFailed;
                final received = activeDownload.received.value;
                final total = activeDownload.total.value;

                // Auto-close on Android when installer intent takes over
                if (isInstalling && Platform.isAndroid) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted && Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  });
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icon + title
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isFailed
                                ? _C.error.withValues(alpha: 0.15)
                                : Colors.orangeAccent
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            isFailed
                                ? Icons.error_outline_rounded
                                : isInstalling
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.download_rounded,
                            color: isFailed
                                ? _C.error
                                : isInstalling
                                    ? const Color(0xFF2D7A4F)
                                    : Colors.orangeAccent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isInstalling
                                    ? 'Installing...'
                                    : isFailed
                                        ? 'Download Failed'
                                        : 'Downloading Update',
                                style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: Colors.white),
                              ),
                              Text(
                                'v${activeDownload.newVersion}',
                                style: GoogleFonts.outfit(
                                    fontSize: 12, color: Colors.white38),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Progress bar
                    if (!isFailed) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: isInstalling
                              ? 1.0
                              : (progress > 0 ? progress : null),
                          minHeight: 8,
                          backgroundColor: _C.border,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isInstalling
                                ? const Color(0xFF2D7A4F)
                                : Colors.orangeAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isInstalling
                                ? 'Installing...'
                                : total > 0
                                    ? '${_fmt(received)} / ${_fmt(total)}'
                                    : _fmt(received),
                            style: GoogleFonts.outfit(
                                fontSize: 12, color: Colors.white38),
                          ),
                          if (total > 0 && !isInstalling)
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orangeAccent),
                            ),
                        ],
                      ),
                    ],

                    // Error message
                    if (isFailed) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _C.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _C.error.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'The download could not be completed. '
                          'Check your internet connection and try again.',
                          style: GoogleFonts.outfit(
                              fontSize: 12, color: _C.error, height: 1.4),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Actions
                    if (!isInstalling)
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: isFailed ? onRetry : onCancel,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 13),
                                decoration: BoxDecoration(
                                  color: isFailed
                                      ? Colors.orangeAccent
                                      : _C.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: isFailed
                                          ? Colors.orangeAccent
                                          : _C.border,
                                      width: 1.5),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  isFailed ? 'Retry' : 'Cancel',
                                  style: GoogleFonts.outfit(
                                    color: isFailed
                                        ? Colors.black
                                        : Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!isFailed) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFF9800),
                                        Color(0xFFFF6D00)
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Run in Background',
                                    style: GoogleFonts.outfit(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared sub-widgets ────────────────────────────────────────────────────────
class _VersionChip extends StatelessWidget {
  final String label;
  final String version;
  final bool muted;
  const _VersionChip(
      {required this.label, required this.version, required this.muted});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.outfit(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white24,
                letterSpacing: 1.2)),
        const SizedBox(height: 2),
        Text(version,
            style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: muted ? Colors.white38 : Colors.orangeAccent,
                letterSpacing: -0.5)),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TextAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Text(label,
            style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white38)),
      ),
    );
  }
}
