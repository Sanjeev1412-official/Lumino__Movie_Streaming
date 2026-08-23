import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lumino_app_moviestreaming/download_hud.dart';
import 'package:lumino_app_moviestreaming/videoplayer.dart';
import 'package:intl/intl.dart';
import 'package:lumino_app_moviestreaming/watch_history_service.dart';
import 'package:lumino_app_moviestreaming/profile_button.dart';

String _formatBytes(double? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String _formatSpeed(double? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond <= 0) return '0 B/s';
  if (bytesPerSecond < 1024) return '${bytesPerSecond.toStringAsFixed(1)} B/s';
  if (bytesPerSecond < 1024 * 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  if (bytesPerSecond < 1024 * 1024 * 1024) return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
}

String _formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

class MyDownloadsPage extends StatelessWidget {
  const MyDownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0D12),
      appBar: AppBar(
        title: const Text('Downloads', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [
          ProfileButton(),
          SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Section: Downloading
          SliverToBoxAdapter(
            child: ValueListenableBuilder<Map<String, DownloadEntry>>(
              valueListenable: DownloadManager().activeDownloadsNotifier,
              builder: (context, active, child) {
                if (active.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('Downloading', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFB561))),
                    ),
                    ...active.values.map((entry) => _DownloadingTile(
                          entry: entry,
                          speed: _formatSpeed(entry.networkSpeed),
                          remaining: _formatDuration(entry.timeRemaining),
                        )),
                  ],
                );
              },
            ),
          ),

          // Section: Downloaded
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Downloaded', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.9))),
            ),
          ),
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: DownloadManager().completedDownloadsNotifier,
            builder: (context, allDownloads, child) {
        // Filter out any posters that might have been accidentally saved in the past
        final downloads = allDownloads.where((item) {
          final path = item['path'] ?? '';
          final filename = item['filename'] ?? '';
          return !path.contains('/posters/') && !filename.contains('_poster.');
        }).toList();

        if (downloads.isEmpty) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_for_offline_outlined, size: 80, color: Colors.white10),
                  SizedBox(height: 16),
                  Text(
                    'No Downloads Yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white30),
                  ),
                ],
              ),
            ),
          );
        }
        final isDesktop = MediaQuery.of(context).size.width >= 800;
        final crossAxisCount = isDesktop ? 3 : (MediaQuery.of(context).size.width >= 600 ? 2 : 1);

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisExtent: 116, // Fixed height for tiles instead of aspect ratio
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = downloads[index];
                return _DownloadedTile(
                  item: item,
                  onDelete: () => DownloadManager().deleteCompletedDownload(item['taskId']),
                );
              },
              childCount: downloads.length,
            ),
          ),
        );
            },
          ),
        ],
      ),
    );
  }
}

class _DownloadingTile extends StatelessWidget {
  final DownloadEntry entry;
  final String speed;
  final String remaining;

  const _DownloadingTile({
    required this.entry,
    required this.speed,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final meta = DownloadTaskMeta.fromMetaData(entry.task.metaData);
    final title = meta.title;
    final quality = meta.quality;
    final progress = entry.progress.clamp(0.0, 1.0);

    // Estimate bytes based on speed and time remaining
    double? totalBytes = meta.totalSize;
    double? downloadedBytes;

    if (totalBytes != null) {
      downloadedBytes = totalBytes * progress;
    } else if (entry.networkSpeed != null &&
        entry.networkSpeed! > 0 &&
        entry.timeRemaining != null &&
        progress > 0 &&
        progress < 1.0) {
      totalBytes = (entry.networkSpeed! * entry.timeRemaining!.inSeconds) /
          (1.0 - progress);
      downloadedBytes = totalBytes * progress;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1F222B).withValues(alpha: 0.8),
            const Color(0xFF14161D).withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFE3B5), Color(0xFFFFB561)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB561).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.download_rounded, color: Colors.black, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (quality.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: Text(
                                  quality,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFFFB561),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$speed • $remaining',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (downloadedBytes != null && totalBytes != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: const Color(0xFFFFB561).withValues(alpha: 0.8),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => DownloadManager().cancelTask(entry.task.taskId),
                    icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.4), size: 20),
                  ),
                ],
              ),
            ),
            // Progress Bar at the very bottom of the tile
            Container(
              height: 4,
              width: double.infinity,
              color: Colors.white.withValues(alpha: 0.05),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFE3B5), Color(0xFFFFB561), Color(0xFFEB8D2E)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadedTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onDelete;

  const _DownloadedTile({required this.item, required this.onDelete});

  String _getFileSize(String path, double? savedSize) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = file.lengthSync().toDouble();
        return _formatBytes(bytes);
      }
    } catch (_) {}
    
    // Fallback to metadata size if file not on disk (synced from other device)
    if (savedSize != null && savedSize > 0) {
      return _formatBytes(savedSize);
    }
    
    return 'Unknown size';
  }

  @override
  Widget build(BuildContext context) {
    final title = item['title'] ?? 'Unknown Title';
    final quality = item['quality'] ?? '';
    final date = DateFormat('MMM dd, yyyy').format(DateTime.parse(item['date']));
    
    // Try to get size from metadata first if available
    final double? savedSize = item['totalSize'] is num 
        ? (item['totalSize'] as num).toDouble() 
        : null;
        
    final size = _getFileSize(item['path'], savedSize);

    return Dismissible(
      key: Key(item['taskId']),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 28),
      ),
      child: InkWell(
          onTap: () async {
            final history = await WatchHistoryService.getProgressByFullTitle(title, isOffline: true);
            Duration? resumePos;
            if (history != null && history.position > 0) {
              resumePos = Duration(milliseconds: history.position);
            }

            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(
                    videoUrl: item['path'],
                    title: title,
                    isOffline: true,
                    episodeTitle: '',
                    initialPosition: resumePos,
                    tmdbId: item['tmdbId'],
                    primeboxUrl: item['primeboxUrl'],
                    posterPath: item['posterPath'],
                    isTvShow: item['mediaType'] == 'tv' || item['mediaType'] == 'series',
                    initialSeason: item['season'],
                    initialEpisode: item['episode'],
                  ),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF171B26).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Poster Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 60,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item['posterPath'] != null)
                          CachedNetworkImage(
                            imageUrl: item['posterPath']!.startsWith('http') 
                              ? item['posterPath']! 
                              : 'https://image.tmdb.org/t/p/w185${item['posterPath']}',
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => const Icon(Icons.movie_rounded, color: Colors.white24, size: 28),
                          )
                        else
                          const Icon(Icons.movie_rounded, color: Colors.white24, size: 28),
                        
                        // Play Button overlay
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFB561).withValues(alpha: 0.9),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                )
                              ],
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                          ),
                        ),

                        // Poster Progress Bar
                        FutureBuilder<WatchHistoryItem?>(
                          future: WatchHistoryService.getProgressByFullTitle(title, isOffline: true),
                          builder: (context, snapshot) {
                            final history = snapshot.data;
                            if (history == null || history.position <= 0) return const SizedBox.shrink();
                            final progress = (history.position / history.duration).clamp(0.0, 1.0);
                            return Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 3,
                                color: Colors.black45,
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress,
                                  child: Container(color: const Color(0xFFFFB561)),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Meta Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (quality.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB561).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                quality,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFFFB561),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            size,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        date,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.3),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      
                      // Progress Indicator
                      FutureBuilder<WatchHistoryItem?>(
                        future: WatchHistoryService.getProgressByFullTitle(title, isOffline: true),
                        builder: (context, snapshot) {
                          final history = snapshot.data;
                          if (history == null || history.position <= 0) return const SizedBox.shrink();

                          final progress = (history.position / history.duration).clamp(0.0, 1.0);
                          final watched = Duration(milliseconds: history.position);
                          final watchedStr = watched.inHours > 0 
                              ? '${watched.inHours}h ${watched.inMinutes.remainder(60)}m'
                              : '${watched.inMinutes}m';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFB561)),
                                        minHeight: 3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    watchedStr,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFFFB561),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // Swipe Indicator or Delete Button
                IconButton(
                  onPressed: () {
                    showGeneralDialog<bool>(
                      context: context,
                      barrierDismissible: true,
                      barrierLabel: 'Delete Download',
                      barrierColor: Colors.black.withValues(alpha: 0.8),
                      transitionDuration: const Duration(milliseconds: 300),
                      pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
                      transitionBuilder: (ctx, anim1, anim2, child) {
                        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
                        return ScaleTransition(
                          scale: curve,
                          child: FadeTransition(
                            opacity: anim1,
                            child: Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 320),
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F111E).withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      blurRadius: 30,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Glowing Delete/Warning Icon
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF4949).withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFFFF4949).withValues(alpha: 0.25),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.delete_forever_rounded,
                                        size: 32,
                                        color: Color(0xFFFF4949),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    
                                    // Dialog Title
                                    const Text(
                                      'Delete Download?',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    
                                    // Description
                                    const Text(
                                      'This will permanently remove the video from your storage.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13.5,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    
                                    // Actions
                                    Row(
                                      children: [
                                        // Keep Button
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => Navigator.pop(ctx),
                                            borderRadius: BorderRadius.circular(16),
                                            child: Container(
                                              height: 46,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.05),
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: Colors.white.withValues(alpha: 0.08),
                                                ),
                                              ),
                                              child: Text(
                                                'Keep',
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.8),
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        
                                        // Delete Button
                                        Expanded(
                                          child: InkWell(
                                            onTap: () {
                                              onDelete();
                                              Navigator.pop(ctx);
                                            },
                                            borderRadius: BorderRadius.circular(16),
                                            child: Container(
                                              height: 46,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFFFF4949),
                                                    Color(0xFFFF2E2E),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius: BorderRadius.circular(16),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFFFF4949).withValues(alpha: 0.35),
                                                    blurRadius: 12,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: const Text(
                                                'Delete',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
