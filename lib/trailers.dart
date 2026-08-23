// ignore_for_file: dead_code, dead_null_aware_expression, deprecated_member_use, use_build_context_synchronously
// lib/trailer.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:lumino_app_moviestreaming/toast.dart';
import 'package:lumino_app_moviestreaming/videoplayer.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as ytex;

// ---------- YOUTUBE RESOLVER ----------

class ResolvedYoutubeStream {
  final String url;
  final String qualityLabel;

  ResolvedYoutubeStream(this.url, this.qualityLabel);
}

final ytex.YoutubeExplode _yt = ytex.YoutubeExplode();

Future<ResolvedYoutubeStream?> _resolveYoutubeHighestStream(
  String youtubeId,
) async {
  try {
    String id = youtubeId.trim();
    if (id.contains('youtube.com') || id.contains('youtu.be')) {
      final uri = Uri.parse(id);
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) {
        id = v;
      } else if (uri.pathSegments.isNotEmpty) {
        id = uri.pathSegments.last;
      }
    }

    final manifest = await _yt.videos.streamsClient.getManifest(id);

    final muxed = manifest.muxed.toList();
    if (muxed.isEmpty) {
      if (kDebugMode) debugPrint('YT: no muxed streams for $id');
      return null;
    }

    // DEBUG: log all muxed streams
    if (kDebugMode) {
      for (final s in muxed) {
        debugPrint(
          'YT muxed: '
          'res=${s.videoResolution.height}, '
          'label=${s.videoQualityLabel}, '
          'container=${s.container.name}, '
          'bitrate=${s.bitrate.kiloBitsPerSecond}kbps',
        );
      }
    }

    // Sort by resolution desc → bitrate desc (DO NOT filter by container)
    muxed.sort((a, b) {
      final ah = a.videoResolution.height;
      final bh = b.videoResolution.height;
      if (ah != bh) return bh.compareTo(ah); // higher resolution first
      return b.bitrate.compareTo(a.bitrate); // then higher bitrate
    });

    final best = muxed.first;
    final label =
        best.videoQualityLabel ?? '${best.videoResolution.height}p';

    if (kDebugMode) {
      debugPrint(
        'YT best muxed: res=${best.videoResolution.height}, '
        'label=$label, container=${best.container.name}, '
        'bitrate=${best.bitrate.kiloBitsPerSecond}kbps',
      );
    }

    return ResolvedYoutubeStream(best.url.toString(), label);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('YT resolve error for "$youtubeId": $e');
    }
    return null;
  }
}


// ---------- TRAILER BOTTOM SHEET ----------

class Trailer extends StatefulWidget {
  final String title; // Movie/series title
  final String? imdbId; // tt1234567
  final String? type; // 'movie' or 'tv'
  final String? directUrl; // NEW: Direct mp4/m3u8 trailer URL

  const Trailer({
    super.key,
    required this.title,
    required this.imdbId,
    required this.type,
    this.directUrl,
  });

  @override
  State<Trailer> createState() => _TrailerState();
}

class _TrailerState extends State<Trailer> {
  late Future<List<TrailerItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchTrailers();
  }

  Future<List<TrailerItem>> _fetchTrailers() async {
    final items = <TrailerItem>[];

    // Add direct Primebox trailer first if available
    if (widget.directUrl != null && widget.directUrl!.isNotEmpty) {
      items.add(TrailerItem(
        name: 'Official Trailer',
        youtubeId: '', // Not a YouTube trailer
        directUrl: widget.directUrl,
        quality: 'HD',
      ));
    }

    if (widget.imdbId == null || widget.imdbId!.isEmpty) {
      if (kDebugMode) debugPrint('Trailer: imdbId is null/empty. Returning direct items.');
      return items;
    }

    final isMovie = (widget.type ?? 'movie').toLowerCase() == 'movie';
    final typePath = isMovie ? 'movies' : 'tv';
    

    final uri = Uri.parse(
      'https://api.simkl.com/$typePath/${widget.imdbId}'
      '?extended=full&client_id=c024bfad7cd0fb2e96ee39bde85e7ae1c3449defe5a6832338fb5ba9adcc139f',
    );

    if (kDebugMode) {
      debugPrint('SIMKL trailers GET: $uri');
    }

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode == 404) {
        if (kDebugMode) {
          debugPrint('SIMKL: no entry for ${widget.imdbId} (type=$typePath)');
        }
        return [];
      }

      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('SIMKL trailers error: ${res.statusCode} ${res.body}');
        }
        return [];
      }

      final Map<String, dynamic> j =
          json.decode(res.body) as Map<String, dynamic>;

      final trailersField = j['trailers'];
      final items = <TrailerItem>[];

      void addTrailer({
        required String youtubeId,
        String? name,
        String? quality,
      }) {
        if (youtubeId.isEmpty) return;
        final idx = items.length + 1;
        final baseName = (name != null && name.trim().isNotEmpty)
            ? name.trim()
            : 'Trailer $idx';
        final fullName = (quality != null && quality.trim().isNotEmpty)
            ? '$baseName • $quality'
            : baseName;

        items.add(
          TrailerItem(name: fullName, youtubeId: youtubeId, quality: quality),
        );
      }

      // trailers as LIST
      if (trailersField is List) {
        for (final t in trailersField) {
          if (t is Map<String, dynamic>) {
            final yt = t['youtube']?.toString() ?? '';
            final name = t['name']?.toString();
            final size = t['size']?.toString();
            if (yt.isNotEmpty) {
              addTrailer(youtubeId: yt, name: name, quality: size);
            }
          }
        }
      }
      // trailers as MAP
      else if (trailersField is Map<String, dynamic>) {
        if (trailersField['youtube'] is String) {
          addTrailer(
            youtubeId: trailersField['youtube'].toString(),
            name: trailersField['name']?.toString(),
            quality: trailersField['size']?.toString(),
          );
        } else {
          for (final value in trailersField.values) {
            if (value is Map<String, dynamic>) {
              final yt = value['youtube']?.toString() ?? '';
              final name = value['name']?.toString();
              final size = value['size']?.toString();
              if (yt.isNotEmpty) {
                addTrailer(youtubeId: yt, name: name, quality: size);
              }
            } else if (value is List) {
              for (final v in value) {
                if (v is Map<String, dynamic>) {
                  final yt = v['youtube']?.toString() ?? '';
                  final name = v['name']?.toString();
                  final size = v['size']?.toString();
                  if (yt.isNotEmpty) {
                    addTrailer(youtubeId: yt, name: name, quality: size);
                  }
                }
              }
            }
          }
        }
      }

      if (kDebugMode) {
        debugPrint('SIMKL trailers parsed: ${items.length}');
      }

      return items;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SIMKL trailers exception: $e');
      }
      return items; // Return what we have (e.g. directUrl)
    }
  }

  Future<void> _playTrailer(TrailerItem item) async {
    // 1. Direct URL Playback (e.g. Primebox MP4)
    if (item.directUrl != null && item.directUrl!.isNotEmpty) {
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            title: widget.title,
            episodeTitle: item.name,
            mediaUrl: item.directUrl!,
            httpSources: null,
            torrentStreams: null,
            initialQuality: item.quality ?? 'HD',
          ),
        ),
      );
      return;
    }

    // 2. YouTube Playback
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    final resolved = await _resolveYoutubeHighestStream(item.youtubeId);
    Navigator.of(context).pop(); // Close loader
    Navigator.of(context).pop(); // Close bottom sheet
    
    if (!mounted) return;

    if (resolved == null) {
      AppToast.show(
        context,
        'Unable to resolve trailer stream.',
        icon: Icons.error_rounded,
        tag: 'Error',
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          title: widget.title,
          episodeTitle: '${item.name} (${resolved.qualityLabel})',
          mediaUrl: resolved.url,
          httpSources: null,
          torrentStreams: null,
          initialQuality: resolved.qualityLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        child: FutureBuilder<List<TrailerItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(height: 32),
                  Center(child: CircularProgressIndicator()),
                  SizedBox(height: 24),
                ],
              );
            }

            final items = snapshot.data ?? const <TrailerItem>[];

            return Column(
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
                        widget.title,
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
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    items.isEmpty
                        ? 'No trailers available.'
                        : 'Choose a trailer to play',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                if (items.isEmpty)
                  const SizedBox(height: 16)
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _TrailerRow(
                          item: item,
                          onTap: () => _playTrailer(item),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}



// --------- MODEL + ROW WIDGET ----------

class TrailerItem {
  final String name;
  final String youtubeId;
  final String? directUrl;
  final String? quality;

  const TrailerItem({
    required this.name,
    required this.youtubeId,
    this.directUrl,
    this.quality,
  });
}

class _TrailerRow extends StatelessWidget {
  final TrailerItem item;
  final VoidCallback onTap;

  const _TrailerRow({required this.item, required this.onTap});

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
          border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
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
                Icons.play_arrow_rounded,
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
                    'Tap to play trailer',
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

class AppLoader extends StatelessWidget {
  final double size;
  const AppLoader({this.size = 80, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Lottie.asset(
          'assets/animations/loader.json', // your loader path
          repeat: true,
        ),
      ),
    );
  }
}
