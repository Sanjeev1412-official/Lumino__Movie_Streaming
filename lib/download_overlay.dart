// lib/download_overlay.dart

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:lumino_app_moviestreaming/download_hud.dart';

class DownloadOverlay extends StatefulWidget {
  const DownloadOverlay({super.key});

  @override
  State<DownloadOverlay> createState() => _DownloadOverlayState();
}

class _DownloadOverlayState extends State<DownloadOverlay> {
  bool _expanded = true;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  Widget build(BuildContext context) {
    if (!_isWindows) {
      // On Android/iOS/Web: no overlay at all
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<Map<String, DownloadEntry>>(
      valueListenable: DownloadManager().activeDownloadsNotifier,
      builder: (context, map, _) {
        if (map.isEmpty) {
          // No active downloads → hide overlay
          return const SizedBox.shrink();
        }

        final entries = map.values.toList()
          ..sort((a, b) => a.task.filename.compareTo(b.task.filename));

        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _expanded
                  ? _buildExpandedPanel(entries)
                  : _buildCollapsedChip(entries.length),
            ),
          ),
        );
      },
    );
  }

  // ---------- MINIMIZED PILL ----------
  Widget _buildCollapsedChip(int count) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = true),
      child: Container(
        key: const ValueKey('collapsed'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF15151B), Color(0xFF09090E)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // orange puck
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFB45A), Color(0xFFFF8C1A)],
                ),
              ),
              child: const Icon(
                Icons.download_rounded,
                size: 16,
                color: Colors.black,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Downloads ($count)',
              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w700,decoration: TextDecoration
                          .none, // <-- removes underline completely
                      decorationColor: Colors.transparent,
                      decorationStyle: TextDecorationStyle.solid,),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- EXPANDED PANEL ----------
  Widget _buildExpandedPanel(List<DownloadEntry> entries) {
    return Container(
      key: const ValueKey('expanded'),
      width: 360,
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: const Color(0xFF050509).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.85),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1.1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle like your sheet
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),

            // header row – similar to DownloadPage title row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 6, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Minimize',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => setState(() => _expanded = false),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white70,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
            // LIST
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final e = entries[index];
                  return _DownloadRowWindows(entry: e);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- SINGLE ROW ----------
class _DownloadRowWindows extends StatelessWidget {
  final DownloadEntry entry;

  const _DownloadRowWindows({required this.entry});

  bool _isFinished() {
    return entry.status == TaskStatus.complete ||
        entry.status == TaskStatus.failed ||
        entry.status == TaskStatus.canceled ||
        entry.status == TaskStatus.notFound;
  }

  String _statusLabel() {
    switch (entry.status) {
      case TaskStatus.enqueued:
        return 'Waiting…';
      case TaskStatus.running:
        return 'Downloading…';
      case TaskStatus.paused:
        return 'Paused';
      case TaskStatus.complete:
        return 'Completed';
      case TaskStatus.failed:
        return 'Failed';
      case TaskStatus.canceled:
        return 'Canceled';
      case TaskStatus.notFound:
        return 'File not found';
      case TaskStatus.waitingToRetry:
        return 'Retrying…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filename = entry.task.filename;
    final title = entry.task.metaData.toString().isNotEmpty == true
        ? entry.task.metaData.toString()
        : filename;

    final p = entry.progress.clamp(0.0, 1.0);
    final percent = (p * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF171B26), Color(0xFF090A10)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // title + cancel
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFE3B5), Color(0xFFFFB561)],
                    ),
                  ),
                  child: const Icon(
                    Icons.movie_outlined,
                    size: 16,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      decoration: TextDecoration
                          .none, // <-- removes underline completely
                      decorationColor: Colors.transparent,
                      decorationStyle: TextDecorationStyle.solid,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (!_isFinished())
                  IconButton(
                    tooltip: 'Cancel download',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                    onPressed: () =>
                        DownloadManager().cancelTask(entry.task.taskId),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // progress bar – styled similar to your sheet
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF272A35),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _isFinished() ? 1.0 : p,
                          child: Container(
                            decoration: const BoxDecoration(
                              borderRadius: BorderRadius.all(
                                Radius.circular(999),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Color(0xFFFFE3B5),
                                  Color(0xFFFFB561),
                                  Color(0xFFEB8D2E),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),

            // status + percent
            Row(
              children: [
                Text(
                  _statusLabel(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                    decoration:
                        TextDecoration.none, // <-- removes underline completely
                    decorationColor: Colors.transparent,
                    decorationStyle: TextDecorationStyle
                        .solid, // 👈 same vibe as "Choose a quality to download"
                  ),
                ),
                const Spacer(),
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                    decoration:
                        TextDecoration.none, // <-- removes underline completely
                    decorationColor: Colors.transparent,
                    decorationStyle: TextDecorationStyle.solid,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
