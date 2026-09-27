import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lumino_app_moviestreaming/download_hud.dart';
import 'package:lumino_app_moviestreaming/profile_button.dart';
import 'package:lumino_app_moviestreaming/toast.dart';
import 'package:lumino_app_moviestreaming/videoplayer.dart';
import 'package:lumino_app_moviestreaming/watch_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloads',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Offline content & media player',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: const [
          ProfileButton(),
          SizedBox(width: 12),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Section: Quick Player Tools (Play Local & Network Stream)
          SliverToBoxAdapter(
            child: _buildQuickActionCards(context),
          ),
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
                      child: Text(
                        'Downloading',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFB561),
                        ),
                      ),
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
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'Downloaded',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: DownloadManager().completedDownloadsNotifier,
            builder: (context, allDownloads, child) {
              final downloads = allDownloads.where((item) {
                final path = item['path'] ?? '';
                final filename = item['filename'] ?? '';
                return !path.contains('/posters/') && !filename.contains('_poster.');
              }).toList();

              if (downloads.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.download_for_offline_outlined,
                            size: 64,
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No Downloads Yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final isDesktop = MediaQuery.of(context).size.width >= 800;
              final crossAxisCount = isDesktop ? 3 : (MediaQuery.of(context).size.width >= 600 ? 2 : 1);

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisExtent: 116,
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

  Widget _buildQuickActionCards(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildActionCard(
                    context: context,
                    title: 'Play Local',
                    subtitle: 'Device storage video',
                    icon: Icons.folder_open_rounded,
                    isHighlighted: false,
                    onTap: () => _pickAndPlayLocal(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionCard(
                    context: context,
                    title: 'Network Stream',
                    subtitle: 'Direct URL / M3U8 link',
                    icon: Icons.link_rounded,
                    isHighlighted: true,
                    onTap: () => _openNetworkStreamModal(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isHighlighted,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141724),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHighlighted
              ? const Color(0xFFFFB561).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.07),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          if (isHighlighted)
            BoxShadow(
              color: const Color(0xFFFFB561).withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: const Color(0xFFFFB561).withValues(alpha: 0.15),
          highlightColor: Colors.white.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isHighlighted
                            ? const Color(0xFFFFB561).withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isHighlighted
                              ? const Color(0xFFFFB561).withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: isHighlighted
                            ? const Color(0xFFFFB561)
                            : Colors.white70,
                        size: 20,
                      ),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 13,
                        color: isHighlighted
                            ? const Color(0xFFFFB561).withValues(alpha: 0.7)
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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
  }

  Future<void> _pickAndPlayLocal(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4',
          'mkv',
          'avi',
          'mov',
          'webm',
          'ts',
          'm4v',
          '3gp',
          'flv',
          'wmv',
        ],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null || filePath.isEmpty) {
        if (context.mounted) {
          AppToast.show(context, 'Could not access the selected file');
        }
        return;
      }

      final rawName = result.files.single.name;
      final dotIdx = rawName.lastIndexOf('.');
      final cleanTitle = (dotIdx != -1) ? rawName.substring(0, dotIdx) : rawName;

      final history = await WatchHistoryService.getProgressByFullTitle(cleanTitle, isOffline: true);
      Duration? resumePos;
      if (history != null && history.position > 0) {
        resumePos = Duration(milliseconds: history.position);
      }

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(
              videoUrl: filePath,
              title: cleanTitle,
              episodeTitle: '',
              isOffline: true,
              initialPosition: resumePos,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error picking local file: $e');
      if (context.mounted) {
        AppToast.show(context, 'Error opening file');
      }
    }
  }

  void _openNetworkStreamModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _NetworkStreamBottomSheet(),
    );
  }
}

class _RecentStreamItem {
  final String url;
  final String title;
  final Map<String, String> headers;

  _RecentStreamItem({
    required this.url,
    required this.title,
    this.headers = const {},
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'headers': headers,
      };

  factory _RecentStreamItem.fromJson(dynamic data) {
    if (data is Map) {
      final h = data['headers'];
      return _RecentStreamItem(
        url: data['url']?.toString() ?? '',
        title: data['title']?.toString() ?? '',
        headers: h is Map ? Map<String, String>.from(h) : const {},
      );
    }
    return _RecentStreamItem(url: data?.toString() ?? '', title: '');
  }
}

class _NetworkStreamBottomSheet extends StatefulWidget {
  const _NetworkStreamBottomSheet();

  @override
  State<_NetworkStreamBottomSheet> createState() => _NetworkStreamBottomSheetState();
}

class _NetworkStreamBottomSheetState extends State<_NetworkStreamBottomSheet> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _userAgentController = TextEditingController();
  final TextEditingController _refererController = TextEditingController();
  final TextEditingController _customHeadersController = TextEditingController();

  bool _isLive = false;
  bool _showHeaders = false;
  List<_RecentStreamItem> _recentItems = [];

  static const String _prefRecentKey = 'lumino_recent_streams_v3';

  static const String _chromeUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const String _vlcUa = 'VLC/3.0.18 LibVLC/3.0.18';
  static const String _safariUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  static const String _exoPlayerUa = 'ExoPlayerPlayback/2.19.0 (Linux; Android 13)';

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _checkClipboard();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _userAgentController.dispose();
    _refererController.dispose();
    _customHeadersController.dispose();
    super.dispose();
  }

  bool get _hasActiveHeaders =>
      _userAgentController.text.trim().isNotEmpty ||
      _refererController.text.trim().isNotEmpty ||
      _customHeadersController.text.trim().isNotEmpty;

  void _checkAndParsePipeUrl(String input) {
    final trimmed = input.trim();
    if (!trimmed.contains('|')) return;

    final parts = trimmed.split('|');
    final cleanUrl = parts[0].trim();
    final headersQuery = parts.sublist(1).join('|').trim();

    _urlController.text = cleanUrl;
    final pairs = headersQuery.split('&');
    final customLines = <String>[];

    for (final pair in pairs) {
      final eq = pair.indexOf('=');
      if (eq != -1) {
        final key = pair.substring(0, eq).trim();
        final val = Uri.decodeComponent(pair.substring(eq + 1).trim());
        if (key.toLowerCase() == 'user-agent') {
          _userAgentController.text = val;
        } else if (key.toLowerCase() == 'referer') {
          _refererController.text = val;
        } else {
          customLines.add('$key: $val');
        }
      }
    }
    if (customLines.isNotEmpty) {
      _customHeadersController.text = customLines.join('\n');
    }
    setState(() {
      _showHeaders = true;
    });
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.startsWith('http://') || text.startsWith('https://') || text.startsWith('rtsp://')) {
        if (mounted && _urlController.text.isEmpty) {
          if (text.contains('|')) {
            _checkAndParsePipeUrl(text);
          } else {
            _urlController.text = text;
          }
          if (text.contains('.m3u8') || text.contains('live')) {
            _isLive = true;
          }
          setState(() {});
        }
      }
    } catch (_) {}
  }

  Future<void> _loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefRecentKey) ?? [];
      final parsed = <_RecentStreamItem>[];
      for (final raw in list) {
        try {
          final decoded = jsonDecode(raw);
          parsed.add(_RecentStreamItem.fromJson(decoded));
        } catch (_) {
          if (raw.isNotEmpty) {
            parsed.add(_RecentStreamItem(url: raw, title: ''));
          }
        }
      }
      if (mounted) setState(() => _recentItems = parsed);
    } catch (_) {}
  }

  Future<void> _saveRecentStream(String url, String title, Map<String, String> headers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = List<_RecentStreamItem>.from(_recentItems);
      current.removeWhere((item) => item.url == url);
      current.insert(0, _RecentStreamItem(url: url, title: title, headers: headers));
      if (current.length > 5) current.removeRange(5, current.length);

      final encoded = current.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_prefRecentKey, encoded);
    } catch (_) {}
  }

  Future<void> _removeRecentStream(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = List<_RecentStreamItem>.from(_recentItems);
      if (index >= 0 && index < current.length) {
        current.removeAt(index);
        final encoded = current.map((e) => jsonEncode(e.toJson())).toList();
        await prefs.setStringList(_prefRecentKey, encoded);
        if (mounted) setState(() => _recentItems = current);
      }
    } catch (_) {}
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{};
    final ua = _userAgentController.text.trim();
    if (ua.isNotEmpty) headers['User-Agent'] = ua;

    final ref = _refererController.text.trim();
    if (ref.isNotEmpty) headers['Referer'] = ref;

    final custom = _customHeadersController.text.trim();
    if (custom.isNotEmpty) {
      final lines = custom.split('\n');
      for (final line in lines) {
        final colon = line.indexOf(':');
        if (colon != -1) {
          final k = line.substring(0, colon).trim();
          final v = line.substring(colon + 1).trim();
          if (k.isNotEmpty && v.isNotEmpty) {
            headers[k] = v;
          }
        }
      }
    }
    return headers;
  }

  void _onPlay() {
    var rawInput = _urlController.text.trim();
    if (rawInput.contains('|')) {
      _checkAndParsePipeUrl(rawInput);
      rawInput = _urlController.text.trim();
    }

    if (rawInput.isEmpty) {
      AppToast.show(context, 'Please enter a stream link');
      return;
    }

    var url = rawInput;
    if (!url.startsWith('http://') &&
        !url.startsWith('https://') &&
        !url.startsWith('rtsp://') &&
        !url.startsWith('rtmp://')) {
      url = 'https://$url';
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      AppToast.show(context, 'Please enter a valid URL');
      return;
    }

    var title = _titleController.text.trim();
    if (title.isEmpty) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final last = segments.last;
        final dot = last.lastIndexOf('.');
        title = dot != -1 ? last.substring(0, dot) : last;
      }
      if (title.isEmpty) title = uri.host;
      if (title.isEmpty) title = 'Network Stream';
    }

    final headers = _buildHeaders();
    _saveRecentStream(url, title, headers);
    Navigator.pop(context);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          title: title,
          episodeTitle: _isLive ? 'Live Stream' : 'Network Stream',
          mediaUrl: url,
          httpSources: {
            'auto': {
              'Stream': url,
            },
          },
          httpMetadata: {
            'direct': {'headers': headers},
            'http|auto|Stream': {'headers': headers},
            'headers': headers,
          },
          isOffline: false,
          isLiveTv: _isLive,
        ),
      ),
    );
  }

  Widget _buildUaPresetChip(String name, String ua) {
    final isSelected = _userAgentController.text.trim() == ua;
    return InkWell(
      onTap: () {
        _userAgentController.text = ua;
        setState(() {});
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFB561).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFB561).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          name,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFB561) : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: const Color(0xFF141721),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'Network Stream',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Play any video URL, HLS (.m3u8), or DASH stream',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _urlController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                keyboardType: TextInputType.url,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Stream link (e.g. https://.../video.m3u8)',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFFFFB561), size: 20),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_urlController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white38),
                          onPressed: () {
                            _urlController.clear();
                            setState(() {});
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.content_paste_rounded, size: 18, color: Colors.white54),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          final text = data?.text?.trim() ?? '';
                          if (text.isNotEmpty) {
                            if (text.contains('|')) {
                              _checkAndParsePipeUrl(text);
                            } else {
                              _urlController.text = text;
                            }
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFFFB561)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onChanged: (text) {
                  if (text.contains('|')) {
                    _checkAndParsePipeUrl(text);
                  } else if (text.contains('.m3u8') || text.contains('live')) {
                    if (!_isLive) setState(() => _isLive = true);
                  }
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Title (optional)',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  prefixIcon: const Icon(Icons.title_rounded, color: Colors.white38, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFFFB561)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Switch(
                    value: _isLive,
                    onChanged: (val) => setState(() => _isLive = val),
                    activeThumbColor: const Color(0xFFFFB561),
                    activeTrackColor: const Color(0xFFFFB561).withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _isLive = !_isLive),
                    child: Text(
                      'Live broadcast / TV stream',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Custom Headers Expander
              GestureDetector(
                onTap: () => setState(() => _showHeaders = !_showHeaders),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _showHeaders
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        color: const Color(0xFFFFB561),
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'HTTP Headers',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(User-Agent, Referer, Auth)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      if (_hasActiveHeaders)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB561).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'CUSTOM',
                            style: TextStyle(
                              color: Color(0xFFFFB561),
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_showHeaders) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _userAgentController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'User-Agent (e.g. VLC/3.0.18 or Mozilla...)',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    prefixIcon: const Icon(Icons.person_outline_rounded, color: Colors.white38, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFB561)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    _buildUaPresetChip('Chrome', _chromeUa),
                    _buildUaPresetChip('VLC', _vlcUa),
                    _buildUaPresetChip('Safari/iOS', _safariUa),
                    _buildUaPresetChip('ExoPlayer', _exoPlayerUa),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _refererController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Referer URL (e.g. https://domain.com/)',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    prefixIcon: const Icon(Icons.open_in_browser_rounded, color: Colors.white38, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFB561)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _customHeadersController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText:
                        'Other headers (one per line, e.g. Origin: https://... or Authorization: Bearer ...)',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFB561)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (_recentItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Recent Streams',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ..._recentItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final hasHeaders = item.headers.isNotEmpty;
                  final display = item.title.isNotEmpty ? item.title : item.url;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.03),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      visualDensity: VisualDensity.compact,
                      leading: const Icon(Icons.history_rounded, size: 16, color: Color(0xFFFFB561)),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              display,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
                          if (hasHeaders) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB561).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'HEADERS',
                                style: TextStyle(
                                  color: Color(0xFFFFB561),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: item.title.isNotEmpty
                          ? Text(
                              item.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 11,
                              ),
                            )
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white24),
                        onPressed: () => _removeRecentStream(index),
                        splashRadius: 16,
                      ),
                      onTap: () {
                        _urlController.text = item.url;
                        _titleController.text = item.title;
                        if (hasHeaders) {
                          _userAgentController.text = item.headers['User-Agent'] ?? '';
                          _refererController.text = item.headers['Referer'] ?? '';
                          final otherHeaders = Map<String, String>.from(item.headers)
                            ..remove('User-Agent')
                            ..remove('Referer');
                          if (otherHeaders.isNotEmpty) {
                            _customHeadersController.text =
                                otherHeaders.entries.map((e) => '${e.key}: ${e.value}').join('\n');
                          }
                          _showHeaders = true;
                        }
                        setState(() {});
                      },
                    ),
                  ),
                );
              }),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _onPlay,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB561),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text(
                    'Play Stream',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
