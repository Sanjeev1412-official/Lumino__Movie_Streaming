// lib/download_page.dart

import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lumino_app_moviestreaming/download_hud.dart';
import 'package:lumino_app_moviestreaming/toast.dart';

/// Simple model for one direct HTTP download option
class DownloadItem {
  final String name; // e.g. "2160p • FSL"
  final String url;
  final Map<String, String>? headers;

  const DownloadItem({required this.name, required this.url, this.headers});
}

/// Bottom-sheet style overlay that lists available links.
/// It only starts the background download; progress UI is via
/// Android/iOS notifications or your own global indicator.
class DownloadPage extends StatelessWidget {
  final String title;
  final List<DownloadItem> items;
  final int? tmdbId;
  final String? mediaType;
  final int? season;
  final int? episode;
  final String? posterPath;
  final String? primeboxUrl;

  const DownloadPage({
    super.key,
    required this.title,
    required this.items,
    this.tmdbId,
    this.mediaType,
    this.season,
    this.episode,
    this.posterPath,
    this.primeboxUrl,
  });

  Future<bool> _startDownload(BuildContext context, DownloadItem item) async {
    // Derive a filename from URL, fallback to title.mp4
    // Sanitize title for filename (Windows/Android don't like colons, etc.)
    final sanitizedTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    String filename = '$sanitizedTitle.mp4';

    final quality = item.name.split(' • ').first;

    // Optional: try to get file size for better progress reporting
    double? totalSize;
    try {
      final res = await http
          .head(
            Uri.parse(item.url),
            headers:
                item.headers ??
                {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                },
          )
          .timeout(const Duration(seconds: 3));
      if (res.headers.containsKey('content-length')) {
        totalSize = double.tryParse(res.headers['content-length']!);
      }
    } catch (_) {}

    final task = DownloadTask(
      url: item.url,
      headers:
          item.headers ??
          {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': item.url.contains('fmoviesunblocked.net')
                ? 'https://fmoviesunblocked.net/'
                : 'https://netfilm.world/',
          },
      filename: filename,
      baseDirectory: BaseDirectory.applicationSupport,
      directory: 'downloads',
      updates: Updates.statusAndProgress,
      allowPause: true,
      metaData: jsonEncode({
        'title': title,
        'quality': quality,
        'totalSize': totalSize,
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        'season': season,
        'episode': episode,
        'posterPath': posterPath,
        'primeboxUrl': primeboxUrl,
      }),
    );

    // 🔥 Download the poster for offline viewing if possible
    final pPath = posterPath;
    if (pPath != null && pPath.isNotEmpty) {
      final posterUrl = pPath.startsWith('http')
          ? pPath
          : 'https://image.tmdb.org/t/p/w500$pPath';
      final posterExt = posterUrl.split('.').last.split('?').first;
      final posterFilename = '${sanitizedTitle}_poster.$posterExt';

      FileDownloader()
          .enqueue(
            DownloadTask(
              url: posterUrl,
              filename: posterFilename,
              baseDirectory: BaseDirectory.applicationSupport,
              directory: 'downloads/posters',
              group: 'posters',
              updates: Updates.status,
            ),
          )
          .then((ok) {
            if (ok) debugPrint('Poster download enqueued: $posterFilename');
          });
    }

    if (item.url.contains('.mpd') ||
        item.url.contains('.m3u8') ||
        item.name.contains('(DASH)')) {
      // Use custom FFmpeg downloader for manifest streams
      final ok = await DownloadManager().processFFmpegDownload(task);
      return ok;
    }

    // 📺 Tell DownloadManager to track it (for Windows overlay)
    DownloadManager().trackTask(task);

    final ok = await FileDownloader().enqueue(task);
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    // Overlay bottom sheet with cinematic styling
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050509).withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 30,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Choose a quality to download',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(height: 12),

            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _DownloadRow(
                    item: item,
                    onTap: () async {
                      final ok = await _startDownload(context, item);
                      if (!context.mounted) return;

                      if (!ok) {
                        AppToast.show(
                          context,
                          'Unable to start download',
                          icon: Icons.error_rounded,
                          tag: 'Error',
                        );
                        return;
                      }

                      // Close the bottom sheet
                      Navigator.of(context).pop();

                      // Optional: show your nice toast AFTER closing
                      AppToast.show(
                        context,
                        'Download started..',
                        icon: Icons.file_download_rounded,
                        tag: 'Download',
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onTap;

  const _DownloadRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF171B26), Color(0xFF090A10)],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE3B5), Color(0xFFFFB561)],
                ),
              ),
              child: const Icon(
                Icons.download_rounded,
                size: 20,
                color: Colors.black,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to download',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
