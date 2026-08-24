// ignore_for_file: deprecated_member_use, unused_element, unused_field, unused_local_variable
// lib/main.dart
// TMDB movie/TV home screen with performance optimizations.

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'dart:io';

import 'package:auto_updater/auto_updater.dart'; // <-- NEW
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, kDebugMode;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

import 'package:lumino_app_moviestreaming/notification_service.dart';

import 'package:lumino_app_moviestreaming/details.dart';
import 'package:lumino_app_moviestreaming/my_downloads_page.dart';
import 'package:lumino_app_moviestreaming/network_service.dart';
import 'package:lumino_app_moviestreaming/search.dart';
import 'package:flutter/gestures.dart';
import 'package:lumino_app_moviestreaming/sync_service.dart';
import 'package:lumino_app_moviestreaming/toast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lumino_app_moviestreaming/watch_history_service.dart';
import 'package:lumino_app_moviestreaming/profile_button.dart';
import 'package:lumino_app_moviestreaming/livetv_page.dart';
import 'package:lumino_app_moviestreaming/update_service.dart';
import 'package:lumino_app_moviestreaming/config/env_config.dart';

class _AppScrollBehavior extends ScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class MovieHomePage extends StatefulWidget {
  const MovieHomePage({super.key});

  static Future<void> prefetchHeroLogos() async {
    // No-op: The new /home endpoint returns fully enriched data instantly.
    // TMDB local enrichment has been removed to improve startup speed.
  }

  @override
  State<MovieHomePage> createState() => _MovieHomePageState();
}

class _MovieHomePageState extends State<MovieHomePage>
    with WidgetsBindingObserver {
  String get apiKey => EnvConfig.tmdbApiKey;

  final String base = 'https://api.tmdb.org/3';
  final String imgW500 = 'https://image.tmdb.org/t/p/w500';
  final String imgW780 = 'https://image.tmdb.org/t/p/w780';

  late final Map<String, String> sections; // path -> label
  late Future<Map<String, List<TmdbItem>>> _sectionsFuture;

  final bool _errorToastShown = false;
  final bool _emptyToastShown = false;
  final bool _networkToastShown = false;

  late StreamSubscription<bool> _netSub;
  late StreamSubscription<void> _syncSub;
  bool _isOnline = true;

  List<WatchHistoryItem> _history = [];
  String _selectedTab = 'Home';

  bool get _isDesktop {
    if (kIsWeb) return false;
    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _isOnline = true;
    _netSub = NetworkService().onStatusChange.listen((online) {
      if (!mounted) return;
      setState(() => _isOnline = online);
    });
    _syncSub = SyncService.onSyncNotify.stream.listen((_) => _loadHistory());
    sections = _buildSections();
    _sectionsFuture = _fetchAllSections(_selectedTab);
    ensureNotificationPermission();

    _initAutoUpdater(); // <-- NEW
    _loadHistory();
    WidgetsBinding.instance.addObserver(this);
    // Initial sync when home screen is first loaded
    SyncService.syncCloudToLocal();

    // Automatic check for update
    Future.delayed(const Duration(seconds: 3), () => _checkForUpdateSilently());

    // Guaranteed delayed FCM token sync to handle startup/reinstall case robustly
    Future.delayed(const Duration(seconds: 5), () {
      NotificationService.syncFcmTokenToCloud();
    });
  }

  Future<void> _checkForUpdateSilently() async {
    if (!mounted) return;
    try {
      await UpdateService().checkForUpdates(context);
    } catch (e) {
      debugPrint('[UpdateService] silent check failed: ');
    }
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App Resumed: Triggering full cloud sync...');
      SyncService.sync();
    }
  }

  Future<void> _loadHistory() async {
    final h = await WatchHistoryService.getHistory();
    // Only show online items in "Continue Watching" (and exclude Live TV)
    final onlineHistory = h
        .where((it) => !it.isOffline && it.episodeTitle != 'Live TV')
        .toList();
    if (mounted) {
      setState(() {
        _history = onlineHistory;
      });
    }
  }

  // ---------- NEW: auto-updater init ----------
  Future<void> _initAutoUpdater() async {
    // --- IMPORTANT: prevent MissingPluginException on mobile/web ---
    if (kIsWeb) return;

    bool isDesktop = false;
    try {
      isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return; // Platform check failed â†’ do nothing
    }

    if (!isDesktop) return; // STOP if not desktop

    // --- Desktop only code starts here ---
    try {
      const feedURL =
          'https://sanjeevsnair.github.io/Lumino_window_Autoupdater/updates/appcast.xml';
      await autoUpdater.setFeedURL(feedURL);
      await autoUpdater.setScheduledCheckInterval(3600);
    } catch (e) {
      debugPrint('auto_updater init failed: $e');
    }
  }

  // ---------- NEW: open check-update screen ----------
  void _openCheckUpdateScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CheckUpdatePage()));
  }

  Future<void> ensureNotificationPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
  }

  Map<String, String> _buildSections() {
    final today = _DateUtil.today();
    final lastWeekStart = _DateUtil.lastWeekStart();
    final nextWeek = _DateUtil.nextWeek();

    return {
      '/trending/all/day?api_key=$apiKey&language=en-US&include_adult=false':
          'Trending Today',
      "/discover/movie?api_key=$apiKey&language=en-US&page=1&sort_by=popularity.desc&with_origin_country=IN"
              "&include_adult=false&include_video=false&primary_release_date.lte=$today":
          'Trending Indian Movies',
      '/movie/popular?api_key=$apiKey&language=en-US&region=US&include_adult=false':
          'Popular Movies',
      '/tv/popular?api_key=$apiKey&language=en-US&region=US':
          'Popular TV Shows',
      '/tv/airing_today?api_key=$apiKey&language=en-US&region=US':
          'Airing Today (TV)',
      '/movie/now_playing?api_key=$apiKey&language=en-US&region=US&include_adult=false&vote_count.gte=50':
          'Now Playing',
      '/tv/on_the_air?api_key=$apiKey&language=en-US&region=US':
          'On The Air (TV)',
      '/movie/upcoming?api_key=$apiKey&language=en-US&region=US&include_adult=false&vote_count.gte=20&primary_release_date.gte=$today&primary_release_date.lte=$nextWeek':
          'Upcoming This Week',
      '/movie/top_rated?api_key=$apiKey&language=en-US&region=US&include_adult=false&vote_count.gte=200':
          'Top Rated Movies',
      '/tv/top_rated?api_key=$apiKey&language=en-US&region=US&vote_count.gte=200':
          'Top Rated TV Shows',
      '/discover/movie?api_key=$apiKey&language=en-US&region=IN'
              '&sort_by=popularity.desc'
              '&include_adult=false&include_video=false'
              '&primary_release_date.gte=$lastWeekStart'
              '&primary_release_date.lte=$today'
              '&vote_count.gte=50'
              '&with_origin_country=IN':
          'Trending Indian Movies',
      '/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc'
              '&with_networks=213&vote_count.gte=50':
          'Netflix',
      '/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc'
              '&with_networks=1024&vote_count.gte=50':
          'Amazon Prime',
      '/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc'
              '&with_networks=2739&vote_count.gte=50':
          'Disney+',
      '/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc'
              '&with_networks=453&vote_count.gte=50':
          'Hulu',
      '/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc'
              '&with_networks=2552&vote_count.gte=50':
          'Apple TV+',
      '/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc'
              '&with_networks=49&vote_count.gte=50':
          'HBO',
      '/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc'
              '&with_networks=4330&vote_count.gte=50':
          'Paramount+',
      '/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc'
              '&with_networks=3353&vote_count.gte=50':
          'Peacock',
      '/discover/tv?api_key=$apiKey&language=en-US'
              '&sort_by=popularity.desc'
              '&with_genres=16'
              '&with_original_language=ja'
              '&vote_count.gte=50':
          'Anime Series',
      '/discover/movie?api_key=$apiKey&language=en-US'
              '&sort_by=popularity.desc'
              '&with_genres=16'
              '&with_original_language=ja'
              '&include_adult=false'
              '&vote_count.gte=50':
          'Anime Movies',
      '/discover/tv?api_key=$apiKey&language=en-US'
              '&sort_by=popularity.desc'
              '&with_original_language=ko'
              '&vote_count.gte=50':
          'Korean Shows',
      '/discover/movie?api_key=$apiKey&language=en-US'
              '&sort_by=popularity.desc'
              '&with_genres=99'
              '&include_adult=false'
              '&vote_count.gte=25':
          'Documentary Movies',
    };
  }

  Future<List<TmdbItem>> _fetchList(String path) async {
    final uri = Uri.parse('$base$path');

    int attempt = 0;
    const int maxAttempts = 3;

    while (attempt < maxAttempts) {
      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final map = json.decode(res.body);
          final list = (map['results'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(TmdbItem.fromJson)
              .where((e) => e.posterPath != null || e.backdropPath != null)
              .take(20)
              .toList();
          return list;
        }

        if (res.statusCode == 429 || res.statusCode >= 500) {
          attempt++;
          await Future.delayed(
            Duration(milliseconds: 300 * (attempt * attempt)),
          );
          continue;
        }

        return const [];
      } catch (e) {
        final isNet =
            e is SocketException ||
            e is TimeoutException ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('Network is unreachable');

        if (isNet) {
          attempt++;
          await Future.delayed(
            Duration(milliseconds: 300 * (attempt * attempt)),
          );
          continue;
        }

        return const [];
      }
    }

    return const [];
  }

  Future<Map<String, List<TmdbItem>>> _fetchAllSections(String tab) async {
    final Map<String, List<TmdbItem>> result = {};

    String url = '${EnvConfig.lambdaUrl}/home';
    if (tab == 'Movies') {
      url = '${EnvConfig.lambdaUrl}/movie';
    } else if (tab == 'Anime') {
      url = '${EnvConfig.lambdaUrl}/animation';
    } else if (tab == 'TV') {
      url = '${EnvConfig.lambdaUrl}/tv';
    }

    try {
      final res = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = json.decode(res.body);

        // New /home endpoint format
        if (body['categories'] != null) {
          final categories = body['categories'] as List;
          final seenSignatures = <String>{};

          for (final cat in categories) {
            final rawCatName = cat['name']?.toString() ?? 'Unknown';
            final results = cat['results'] as List?;
            if (results == null || results.isEmpty) continue;

            final list = <TmdbItem>[];
            for (final item in results) {
              final sid = item['subjectId']?.toString();
              if (sid == null) continue;
              final subjectType = item['subjectType'] ?? (item['type'] == 'TvSeries' ? 2 : 1);
              final isTv = subjectType == 2 || subjectType == 7 || item['type'] == 'TvSeries';
              final mediaType = isTv ? 'tv' : 'movie';

              list.add(
                TmdbItem(
                  id: item['tmdb_id'] ?? 0,
                  mediaType: mediaType,
                  title: item['title']?.toString() ?? '',
                  posterPath: item['poster'] ?? item['posterUrl'],
                  backdropPath: item['background'] ?? item['posterUrl'],
                  logoPath: item['logo'],
                  overview: item['plot'],
                  releaseDate: item['year']?.toString(),
                  voteAverage: double.tryParse(item['score']?.toString() ?? item['rating']?.toString() ?? '0'),
                  movieboxSubjectId: sid,
                ),
              );
            }

            if (list.isNotEmpty) {
              if (rawCatName.trim().toLowerCase() == 'trending') {
                result['HeroBanner'] = list.where((item) => item.overview != null && item.overview!.trim().isNotEmpty).toList();
                result['Trending'] = list;
                final sig = list.map((e) => e.movieboxSubjectId ?? e.title ?? '').take(5).join('|');
                seenSignatures.add(sig);
                continue;
              }

              // Detect duplicate categories (where server returned fallback duplicate list)
              final sig = list.map((e) => e.movieboxSubjectId ?? e.title ?? '').take(5).join('|');
              if (seenSignatures.contains(sig)) {
                // Skip duplicate content category (e.g. broken channel IDs falling back to generic lists)
                continue;
              }
              seenSignatures.add(sig);

              // Normalize category name for clean UI
              String catName = rawCatName.trim();
              if (catName == 'Anime (List)') catName = 'Anime';
              else if (catName == 'Indian (Movies)') catName = 'Indian Movies';
              else if (catName == 'Indian (Series)') catName = 'Indian Series';
              else if (catName == 'USA (Movies)') catName = 'Hollywood Movies';
              else if (catName == 'USA (Series)') catName = 'Western Series';
              else if (catName == 'Japan (Movies)') catName = 'Japanese Movies';
              else if (catName == 'Japan (Series)') catName = 'Japanese Series';
              else if (catName == 'China (Movies)') catName = 'Chinese Movies';
              else if (catName == 'China (Series)') catName = 'Chinese Drama';
              else if (catName == 'South Korean (Movies)') catName = 'Korean Movies';
              else if (catName == 'South Korean (Series)') catName = 'Korean Drama';
              else if (catName == 'Philippines (Movies)') catName = 'Filipino Movies';
              else if (catName == 'Philippines (Series)') catName = 'Filipino Series';
              else if (catName == 'Thailand (Movies)') catName = 'Thai Movies';
              else if (catName == 'Thailand (Series)') catName = 'Thai Series';
              else if (catName == 'Nollywood (Movies)') catName = 'Nollywood Movies';
              else if (catName == 'Nollywood (Series)') catName = 'Nollywood Series';
              else if (catName == 'Action (Movies)') catName = 'Action Movies';
              else if (catName == 'Crime (Movies)') catName = 'Crime Movies';
              else if (catName == 'Comedy (Movies)') catName = 'Comedy Movies';
              else if (catName == 'Romance (Movies)') catName = 'Romance Movies';
              else if (catName == 'Crime (Series)') catName = 'Crime Series';
              else if (catName == 'Comedy (Series)') catName = 'Comedy Series';
              else if (catName == 'Romance (Series)') catName = 'Romance Series';

              if (!result.containsKey(catName)) {
                result[catName] = list;
              }
            }
          }
        } else {
          // Fallback for legacy endpoints (/movie, /animation, /tv)
          final data = body['data'] ?? body;
          List items = [];
          if (data['items'] != null) {
            items = data['items'];
          } else if (data['subjects'] != null) {
            items = data['subjects'];
          } else if (data['operatingList'] != null) {
            for (final op in data['operatingList']) {
              if (op['subjects'] != null) items.addAll(op['subjects']);
              if (op['banner']?['items'] != null) items.addAll(op['banner']['items']);
            }
          }

          if (items.isNotEmpty) {
            final list = <TmdbItem>[];
            for (final item in items) {
              final sid = item['subjectId']?.toString();
              if (sid == null) continue;
              final subjectType = item['subjectType'] ?? 1;
              final isTv = subjectType == 2 || subjectType == 7;
              
              list.add(
                TmdbItem(
                  id: 0,
                  mediaType: isTv ? 'tv' : 'movie',
                  title: item['title']?.toString() ?? '',
                  posterPath: item['cover']?['url'] ?? item['image']?['url'],
                  backdropPath: item['cover']?['url'] ?? item['image']?['url'],
                  voteAverage: double.tryParse(item['imdbRatingValue']?.toString() ?? '0'),
                  releaseDate: item['releaseDate'],
                  movieboxSubjectId: sid,
                ),
              );
            }
            if (list.isNotEmpty) {
              result[tab] = list;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Primebox API error: $e');
    }

    return result;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _netSub.cancel();
    _syncSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop;
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 17, 17, 17),
      body: Stack(
        children: [
          // Background Color Block with smooth gradient to prevent mismatch during top bouncing overscroll
          if (!isDesktop)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 300,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Color.fromARGB(255, 17, 17, 17)],
                  ),
                ),
              ),
            ),
          // Dynamic Background
          ScrollConfiguration(
            behavior: const _AppScrollBehavior(),
            child: FutureBuilder<Map<String, List<TmdbItem>>>(
              future: _sectionsFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: AppLoader(size: 300));
                }

                if (!_isOnline || !snap.hasData || snap.data!.isEmpty) {
                  return _NoNetworkState(
                    onRetry: () {
                      setState(() {
                        _sectionsFuture = _fetchAllSections(_selectedTab);
                      });
                    },
                  );
                }

                final allData = snap.data!;
                final Map<String, List<TmdbItem>> data = {};

                if (_selectedTab == 'Home') {
                  data.addAll(allData);
                } else if (_selectedTab == 'Movies') {
                  data.addAll(
                    Map.fromEntries(
                      allData.entries.where(
                        (e) =>
                            e.key == 'HeroBanner' ||
                            e.key.toLowerCase().contains('movie') ||
                            e.key == 'Trending in Cinema' ||
                            e.key == 'Bollywood' ||
                            e.key == 'South Indian' ||
                            e.key == 'Hollywood' ||
                            (!e.key.toLowerCase().contains('series') && !e.key.toLowerCase().contains('drama')),
                      ),
                    ),
                  );
                } else if (_selectedTab == 'TV') {
                  // Include HeroBanner + anything containing 'tv', 'series', or 'drama'
                  data.addAll(
                    Map.fromEntries(
                      allData.entries.where(
                        (e) =>
                            e.key == 'HeroBanner' ||
                            e.key.toLowerCase().contains('tv') ||
                            e.key.toLowerCase().contains('series') ||
                            e.key.toLowerCase().contains('drama'),
                      ),
                    ),
                  );
                } else if (_selectedTab == 'Anime') {
                  data.addAll(
                    Map.fromEntries(
                      allData.entries.where(
                        (e) =>
                            e.key == 'HeroBanner' ||
                            e.key.toLowerCase().contains('anime') ||
                            e.key.toLowerCase().contains('japan'),
                      ),
                    ),
                  );
                }

                // Robust lookup for Top Series (Case-insensitive)
                final topSeriesKey = data.keys.firstWhere(
                  (k) => k.toLowerCase().contains('top series'),
                  orElse: () => '',
                );

                final heroSource =
                    (_selectedTab == 'TV' && topSeriesKey.isNotEmpty)
                    ? data[topSeriesKey]!
                    : (data.containsKey('HeroBanner')
                          ? data['HeroBanner']!
                          : (data.isNotEmpty
                                ? data.values.firstWhere(
                                    (l) => l.isNotEmpty,
                                    orElse: () => const <TmdbItem>[],
                                  )
                                : const <TmdbItem>[]));
                final heroItems = heroSource.where((item) => item.overview != null && item.overview!.trim().isNotEmpty).take(8).toList();
                final entries = data.entries
                    .where((e) => e.key != 'HeroBanner')
                    .toList();

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: CustomScrollView(
                    key: ValueKey(_selectedTab),
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      // Mobile Top Bar (LUMINO Title) that scrolls with the content
                      if (!isDesktop)
                        SliverToBoxAdapter(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.8),
                                  Colors.black.withValues(alpha: 0.4),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ),
                            ),
                            child: SafeArea(
                              bottom: false,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 10.0,
                                  bottom: 24.0,
                                ),
                                child: Center(
                                  child: Text(
                                    'LUMINO',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFFFFB561),
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 4.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Hero Section
                      if (heroItems.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _ModernHeroCarousel(
                            items: heroItems,
                            imgBase: imgW780,
                            apiKey: apiKey,
                            base: base,
                            imgW185: 'https://image.tmdb.org/t/p/w185',
                            imgW500: imgW500,
                            imgW780: imgW780,
                            isDesktop: isDesktop,
                            onReturn: _loadHistory,
                          ),
                        ),

                      // Continue Watching
                      if (_history.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _ModernContinueWatching(
                            items: _history,
                            apiKey: apiKey,
                            base: base,
                            imgW185: 'https://image.tmdb.org/t/p/w185',
                            imgW500: imgW500,
                            imgW780: imgW780,
                            isDesktop: isDesktop,
                            onRefresh: _loadHistory,
                          ),
                        ),

                      // Live TV Promo Banner
                      SliverToBoxAdapter(
                        child: _ModernLiveTvPromo(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LiveTvPage(),
                              ),
                            );
                          },
                          isDesktop: isDesktop,
                        ),
                      ),

                      // Content Sections
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final entry = entries[i];
                          return _ModernHorizontalSection(
                            title: entry.key,
                            items: entry.value,
                            imgBase: imgW500,
                            apiKey: apiKey,
                            base: base,
                            imgW185: 'https://image.tmdb.org/t/p/w185',
                            imgW500: imgW500,
                            imgW780: imgW780,
                            isDesktop: isDesktop,
                            onReturn: _loadHistory,
                          );
                        }, childCount: entries.length),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ),
                );
              },
            ),
          ),

          Positioned(
            bottom: isDesktop ? 32 : 24,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: _FloatingNavBar(
                  selectedTab: _selectedTab,
                  onTabSelected: (tab) {
                    if (_selectedTab == tab) return;
                    setState(() {
                      _selectedTab = tab;
                      _sectionsFuture = _fetchAllSections(tab);
                    });
                  },
                  onSearch: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            SearchPage(
                              apiKey: apiKey,
                              base: base,
                              imgW185: imgW500,
                              imgW500: imgW500,
                              imgW780: imgW780,
                              initialQuery: '',
                            ),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              const curve = Curves.easeOutQuart;
                              var fadeAnimation = animation.drive(
                                CurveTween(curve: Curves.easeIn),
                              );
                              var scaleAnimation = animation.drive(
                                Tween(
                                  begin: 0.95,
                                  end: 1.0,
                                ).chain(CurveTween(curve: curve)),
                              );

                              return FadeTransition(
                                opacity: fadeAnimation,
                                child: ScaleTransition(
                                  scale: scaleAnimation,
                                  child: child,
                                ),
                              );
                            },
                        transitionDuration: const Duration(milliseconds: 400),
                      ),
                    );
                  },
                  onDownloads: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const MyDownloadsPage(),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              const begin = Offset(0.0, 0.05);
                              const end = Offset.zero;
                              const curve = Curves.easeOutQuart;
                              var tween = Tween(
                                begin: begin,
                                end: end,
                              ).chain(CurveTween(curve: curve));
                              var offsetAnimation = animation.drive(tween);
                              var fadeAnimation = animation.drive(
                                CurveTween(curve: Curves.easeIn),
                              );

                              return FadeTransition(
                                opacity: fadeAnimation,
                                child: SlideTransition(
                                  position: offsetAnimation,
                                  child: child,
                                ),
                              );
                            },
                        transitionDuration: const Duration(milliseconds: 500),
                      ),
                    );
                  },
                  onTapUpdate: _openCheckUpdateScreen,
                  isDesktop: isDesktop,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== Floating Nav Bar =====================

class _FloatingNavBar extends StatelessWidget {
  final String selectedTab;
  final ValueChanged<String> onTabSelected;
  final VoidCallback onSearch;
  final VoidCallback onDownloads;
  final VoidCallback onTapUpdate;
  final bool isDesktop;

  const _FloatingNavBar({
    required this.selectedTab,
    required this.onTabSelected,
    required this.onSearch,
    required this.onDownloads,
    required this.onTapUpdate,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isVerySmall = screenWidth < 360;
    final isSmall = screenWidth < 420;

    final double horizontalMargin = isDesktop ? 20 : (isVerySmall ? 8 : 12);
    final double navHeight = isDesktop ? 64 : (isVerySmall ? 58 : 64);
    final double innerPadding = isDesktop ? 12 : (isVerySmall ? 4 : 8);

    return Container(
      height: navHeight,
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: innerPadding),
            child: isDesktop
                ? _buildDesktopContent()
                : _buildMobileContent(context, isVerySmall),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopContent() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildNavItem(HugeIcons.strokeRoundedHome01, 'Home', 'Home', false),
          const SizedBox(width: 4),
          _buildNavItem(
            HugeIcons.strokeRoundedVideo01,
            'Movies',
            'Movies',
            false,
          ),
          const SizedBox(width: 4),
          _buildNavItem(HugeIcons.strokeRoundedTv01, 'TV', 'TV', false),
          const SizedBox(width: 4),
          _buildNavItem(HugeIcons.strokeRoundedBook01, 'Anime', 'Anime', false),
          Container(
            width: 1,
            height: 20,
            color: Colors.white10,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          _buildActionItem(
            HugeIcons.strokeRoundedSearch01,
            onSearch,
            isSearch: true,
          ),
          const SizedBox(width: 8),
          _buildActionItem(HugeIcons.strokeRoundedDownload01, onDownloads),
          const SizedBox(width: 16),
          ProfileButton(onTapUpdate: onTapUpdate),
        ],
      ),
    );
  }

  Widget _buildMobileContent(BuildContext context, bool isVerySmall) {
    // We use a slightly larger breakpoint for labels to prevent squashing icons
    final screenWidth = MediaQuery.of(context).size.width;
    final hideLabels = screenWidth < 400;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Navigation Group
        Expanded(
          flex: 6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Flexible(
                child: _buildNavItem(
                  HugeIcons.strokeRoundedHome01,
                  'Home',
                  'Home',
                  hideLabels,
                ),
              ),
              Flexible(
                child: _buildNavItem(
                  HugeIcons.strokeRoundedVideo01,
                  'Movies',
                  'Movies',
                  hideLabels,
                ),
              ),
              Flexible(
                child: _buildNavItem(
                  HugeIcons.strokeRoundedTv01,
                  'TV',
                  'TV',
                  hideLabels,
                ),
              ),
              Flexible(
                child: _buildNavItem(
                  HugeIcons.strokeRoundedBook01,
                  'Anime',
                  'Anime',
                  hideLabels,
                ),
              ),
            ],
          ),
        ),

        // Divider
        Container(
          width: 1.5,
          height: 20,
          margin: EdgeInsets.symmetric(horizontal: isVerySmall ? 2 : 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.1),
                Colors.white.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),

        // Actions Group
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionItem(
              HugeIcons.strokeRoundedSearch01,
              onSearch,
              isSearch: true,
              isVerySmall: isVerySmall,
            ),
            _buildActionItem(
              HugeIcons.strokeRoundedDownload01,
              onDownloads,
              isVerySmall: isVerySmall,
            ),
            const SizedBox(width: 4),
            ProfileButton(onTapUpdate: onTapUpdate),
            SizedBox(width: isVerySmall ? 4 : 8),
          ],
        ),
      ],
    );
  }

  Widget _buildNavItem(
    dynamic iconNode,
    String label,
    String tab,
    bool hideLabels,
  ) {
    final isSelected = selectedTab == tab;
    // On mobile, we only show labels if the screen is wide enough AND the item is selected
    final showLabel = isSelected && (isDesktop || !hideLabels);

    return GestureDetector(
      onTap: () => onTabSelected(tab),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutQuart,
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 16 : (showLabel ? 10 : 8),
          vertical: 8,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFB561).withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFB561).withValues(alpha: 0.15)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: iconNode,
              size: isDesktop ? 22.0 : 20.0,
              color: isSelected
                  ? const Color(0xFFFFB561)
                  : Colors.white.withValues(alpha: 0.4),
            ),
            if (showLabel) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFFFB561),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(
    dynamic iconNode,
    VoidCallback onTap, {
    bool isSearch = false,
    bool isVerySmall = false,
  }) {
    return IconButton(
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      splashRadius: 24,
      constraints: BoxConstraints(
        minWidth: isDesktop ? 44 : (isVerySmall ? 34 : 38),
        minHeight: isDesktop ? 44 : (isVerySmall ? 34 : 38),
      ),
      icon: isSearch
          ? Hero(
              tag: 'search-icon',
              child: HugeIcon(
                icon: iconNode,
                color: Colors.white.withValues(alpha: 0.55),
                size: isDesktop ? 22.0 : (isVerySmall ? 19.0 : 21.0),
              ),
            )
          : HugeIcon(
              icon: iconNode,
              color: Colors.white.withValues(alpha: 0.55),
              size: isDesktop ? 22.0 : (isVerySmall ? 19.0 : 21.0),
            ),
      onPressed: onTap,
    );
  }
}

// ===================== Hero Carousel ==================
class _ModernHeroCarousel extends StatefulWidget {
  final List<TmdbItem> items;
  final String imgBase;
  final String apiKey;
  final String base;
  final String imgW185;
  final String imgW500;
  final String imgW780;
  final bool isDesktop;
  final VoidCallback? onReturn;

  const _ModernHeroCarousel({
    required this.items,
    required this.imgBase,
    required this.apiKey,
    required this.base,
    required this.imgW185,
    required this.imgW500,
    required this.imgW780,
    required this.isDesktop,
    this.onReturn,
  });

  @override
  State<_ModernHeroCarousel> createState() => _ModernHeroCarouselState();
}

class _ModernHeroCarouselState extends State<_ModernHeroCarousel> {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: 5000,
      viewportFraction: widget.isDesktop ? 1.0 : 0.60,
    );
    _startTimer();
  }

  @override
  void didUpdateWidget(_ModernHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDesktop != widget.isDesktop) {
      final oldPage = _pageController.hasClients
          ? _pageController.page?.round() ?? 5000
          : 5000;
      _pageController.dispose();
      _pageController = PageController(
        initialPage: oldPage,
        viewportFraction: widget.isDesktop ? 1.0 : 0.60,
      );
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (!mounted || widget.items.isEmpty) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeInOutQuart,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filter out items that don't have an image
    final filteredItems = widget.items.where((item) {
      return item.posterPath != null || item.backdropPath != null;
    }).toList();

    if (filteredItems.isEmpty) return const SizedBox.shrink();
    final size = MediaQuery.of(context).size;
    final double height = widget.isDesktop ? size.height * 0.88 : 360.0;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: 10000, // Large number for pseudo-infinite loop
            onPageChanged: (i) {
              setState(() => _currentIndex = i % filteredItems.length);
              _startTimer();
            },
            itemBuilder: (context, i) {
              final actualIndex = i % filteredItems.length;

              if (!widget.isDesktop) {
                // On mobile, the PageView just handles gestures.
                // We render the actual cards in a custom Stack below to fix Z-index.
                final item = filteredItems[actualIndex];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 500),
                        pageBuilder: (_, anim, _) => FadeTransition(
                          opacity: anim,
                          child: DetailsPage(
                            apiKey: widget.apiKey,
                            base: widget.base,
                            imgW185: widget.imgW185,
                            imgW500: widget.imgW500,
                            imgW780: widget.imgW780,
                            id: item.id,
                            mediaType: item.mediaType,
                            linkApiBase: EnvConfig.luminoBackendUrl,
                            primeboxUrl: item.primeboxUrl,
                            primeboxSubjectType: item.primeboxSubjectType,
                            primeboxType: item.primeboxType,
                            movieboxSubjectId: item.movieboxSubjectId,
                            initialTitle: item.displayTitle,
                            initialBackdrop:
                                item.backdropPath ?? item.posterPath,
                          ),
                        ),
                      ),
                    ).then((_) => widget.onReturn?.call());
                  },
                  child: const SizedBox.expand(),
                );
              }

              return _ModernHeroCard(
                key: ValueKey(
                  'hero-${filteredItems[actualIndex].displayTitle}-$i',
                ),
                item: filteredItems[actualIndex],
                isCenter: actualIndex == _currentIndex,
                apiKey: widget.apiKey,
                base: widget.base,
                imgW185: widget.imgW185,
                imgW500: widget.imgW500,
                imgW780: widget.imgW780,
                isDesktop: widget.isDesktop,
                onReturn: widget.onReturn,
              );
            },
          ),

          // Custom Stack Renderer for Mobile to ensure center card is always ON TOP
          if (!widget.isDesktop)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  // Fallback to the initial page so cards render immediately on the first frame
                  // instead of waiting for the PageController to attach and have dimensions!
                  final double page =
                      (_pageController.hasClients &&
                          _pageController.position.haveDimensions)
                      ? _pageController.page!
                      : 5000.0;
                  final int centerI = page.round();

                  final double cardWidth =
                      size.width * 0.60; // Must match viewportFraction
                  final double spacing = cardWidth;

                  List<Widget> stackChildren = [];

                  // Render order: Left, Right, then Center (so center is drawn last/on top)
                  for (int i in [centerI - 1, centerI + 1, centerI]) {
                    if (i < 0) continue;
                    final double value = i - page;
                    if (value.abs() > 1.5) {
                      continue; // Only render visible cards
                    }

                    final actualIndex = i % filteredItems.length;

                    final double baseTranslateX = value * spacing;
                    final double overlapDx = -value * 35.0; // Overlap amount
                    final double dy = value.abs() * 30.0;
                    final double scale = 1.0 - (value.abs() * 0.1);
                    final double rotationZ = value * 0.20;

                    Widget card = SizedBox(
                      width: cardWidth,
                      child: _ModernHeroCard(
                        key: ValueKey(
                          'hero-mobile-${filteredItems[actualIndex].displayTitle}-$i',
                        ),
                        item: filteredItems[actualIndex],
                        isCenter: i == centerI,
                        apiKey: widget.apiKey,
                        base: widget.base,
                        imgW185: widget.imgW185,
                        imgW500: widget.imgW500,
                        imgW780: widget.imgW780,
                        isDesktop: widget.isDesktop,
                        onReturn: widget.onReturn,
                      ),
                    );

                    stackChildren.add(
                      Positioned(
                        left: (size.width - cardWidth) / 2 + baseTranslateX,
                        top: 0,
                        bottom: 0,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..translate(overlapDx, dy, 0.0)
                            ..scale(scale, scale)
                            ..rotateZ(rotationZ),
                          child: card,
                        ),
                      ),
                    );
                  }

                  return Stack(
                    clipBehavior: Clip.none,
                    children: stackChildren,
                  );
                },
              ),
            ),

          // Cinematic bottom blend gradient for desktop
          if (widget.isDesktop)
            Positioned(
              bottom: -20, // Extra overlap to ensure no bottom edge leak
              left: 0,
              right: 0,
              height: height * 0.7, // Blend starts from 60% height down
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF141414).withValues(alpha: 0.3),
                        const Color(0xFF141414).withValues(alpha: 0.7),
                        const Color(0xFF141414).withValues(alpha: 0.95),
                        const Color.fromARGB(
                          255,
                          17,
                          17,
                          17,
                        ), // Solid to perfectly mask edge
                        const Color.fromARGB(255, 15, 15, 15),
                      ],
                      stops: const [0.0, 0.4, 0.7, 0.9, 0.98, 1.0],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


class _ModernHeroCard extends StatefulWidget {
  final TmdbItem item;
  final bool isCenter;
  final String apiKey;
  final String base;
  final String imgW185;
  final String imgW500;
  final String imgW780;
  final bool isDesktop;
  final VoidCallback? onReturn;

  const _ModernHeroCard({
    super.key,
    required this.item,
    required this.isCenter,
    required this.apiKey,
    required this.base,
    required this.imgW185,
    required this.imgW500,
    required this.imgW780,
    required this.isDesktop,
    this.onReturn,
  });

  @override
  State<_ModernHeroCard> createState() => _ModernHeroCardState();
}

class _ModernHeroCardState extends State<_ModernHeroCard> {

  @override
  Widget build(BuildContext context) {
    if (widget.isDesktop) {
      return _buildDesktopCard(context);
    }
    return _buildMobileCard(context);
  }

  Widget _buildDesktopCard(BuildContext context) {
    final enriched = widget.item;

    final img = enriched.backdropPath ?? enriched.posterPath;
    if (img == null) return Container(color: const Color(0xFF141414));

    final imageUrl = img.startsWith('http')
        ? img
        : 'https://image.tmdb.org/t/p/w1280$img'; // w1280 is faster than original but still high quality

    return GestureDetector(
      onTap: () => _navigateToDetails(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background Image
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(color: Colors.black12),
            errorWidget: (_, _, _) => Container(color: Colors.black26),
          ),

          // 2. Vertical Depth Gradient (Deep Solid Mask from 70%)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  const Color(0xFF141414), // Solid base
                  const Color(0xFF141414).withValues(alpha: 0.98),
                  const Color(0xFF141414).withValues(alpha: 0.7),
                  const Color(0xFF141414).withValues(alpha: 0.2),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.1, 0.4, 0.7, 1.0],
              ),
            ),
          ),

          // 3. Side Edge Blending Gradients (Left and Right for seamless carousel)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF141414), // Solid base at left edge
                  const Color(0xFF141414).withValues(alpha: 0.8), // Text readability
                  Colors.transparent, // Center is visible
                  Colors.transparent, // Center is visible
                  const Color(0xFF141414).withValues(alpha: 0.8), // Right edge blending
                  const Color(0xFF141414), // Solid base at right edge
                ],
                stops: const [0.0, 0.15, 0.4, 0.6, 0.85, 1.0],
              ),
            ),
          ),

          // 4. Content Overlay
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 120),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: 20,
                  left: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 4d. Title Logo
                      Container(
                        height: 180,
                        width: 550,
                        alignment: Alignment.bottomLeft,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: enriched.logoPath != null
                              ? CachedNetworkImage(
                                  key: const ValueKey('logo'),
                                  imageUrl: enriched.logoPath!,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomLeft,
                                  memCacheHeight: 400,
                                  placeholder: (_, _) => const SizedBox.shrink(),
                                )
                              : Padding(
                                  key: const ValueKey('text'),
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    enriched.displayTitle,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 52,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.5,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // 4c. Metadata Row
                      SizedBox(
                        height: 30,
                        child: Row(
                          children: [
                            if (enriched.voteAverage != null &&
                                enriched.voteAverage! > 0) ...[
                              const Icon(
                                Icons.star_rounded,
                                color: Color.fromARGB(255, 0, 255, 98),
                                size: 22,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                enriched.voteAverage!.toStringAsFixed(1),
                                style: GoogleFonts.outfit(
                                  color: const Color.fromARGB(255, 0, 255, 98),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 16),
                              _dot(),
                              const SizedBox(width: 16),
                            ],
                            Text(
                              enriched.yearLabel,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 16),
                            _dot(),
                            const SizedBox(width: 16),
                            Text(
                              enriched.mediaType.toString()[0].toUpperCase() + 
                              enriched.mediaType.toString().substring(1),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (enriched.genres != null &&
                                enriched.genres!.isNotEmpty) ...[
                              const SizedBox(width: 16),
                              _dot(),
                              const SizedBox(width: 16),
                              Text(
                                enriched.genres!.take(2).join(' ,'),
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // 4b. Synopsis
                      SizedBox(
                        width: 700,
                        child: Text(
                          enriched.overview ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 18,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      
                      // 4a. Actions
                      _buildCinematicButton(
                        context,
                        label: 'Play',
                        icon: Icons.play_arrow_rounded,
                        isPrimary: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCard(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

    final enriched = widget.item;
    final img = enriched.posterPath ?? enriched.backdropPath;

    if (img == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(24),
        ),
      );
    }

    final imageUrl = img.startsWith('http') ? img : '${widget.imgW780}$img';

    return GestureDetector(
      onTap: () => _navigateToDetails(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: widget.isCenter
              ? Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Colors.white.withValues(alpha: 0.05)),
                errorWidget: (context, url, error) =>
                    Container(color: Colors.white10),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.9),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: isSmallScreen ? 16 : 24,
                right: isSmallScreen ? 16 : 24,
                bottom: isSmallScreen ? 16 : 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Unified Logo/Title inside the card state
                    widget.item.logoPath != null
                        ? Container(
                            constraints: BoxConstraints(
                              maxWidth: isSmallScreen ? 180 : 280,
                              maxHeight: isSmallScreen ? 60 : 80,
                            ),
                            child: CachedNetworkImage(
                              imageUrl: widget.item.logoPath!,
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomLeft,
                            ),
                          )
                        : Text(
                            widget.item.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isSmallScreen ? 20 : 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                    SizedBox(height: isSmallScreen ? 5 : 12),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _ModernBadge(
                          label: widget.item.typeLabel,
                          color: const Color(0xFFFFB561),
                        ),
                        if (widget.item.voteAverage != null && widget.item.voteAverage! > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color.fromARGB(255, 0, 255, 98),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.item.voteAverage!.toStringAsFixed(1),
                                style: TextStyle(
                                  color: const Color.fromARGB(255, 0, 255, 98),
                                  fontWeight: FontWeight.bold,
                                  fontSize: isSmallScreen ? 10 : 12,
                                ),
                              ),
                            ],
                          ),
                        if (widget.item.yearLabel.isNotEmpty)
                          Text(
                            widget.item.yearLabel,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontWeight: FontWeight.bold,
                              fontSize: isSmallScreen ? 10 : 12,
                            ),
                          ),
                      ],
                    ),
                    if (widget.item.overview != null && widget.item.overview!.isNotEmpty) ...[
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      Text(
                        widget.item.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: isSmallScreen ? 11 : 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot() => Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.3),
      shape: BoxShape.circle,
    ),
  );

  Widget _buildCinematicButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isPrimary,
  }) {
    const baseColor = Color(0xFFFFB561);
    const darkBase = Color(0xFFE28A2B);

    return SizedBox(
      width: 150,
      height: 46,
      child: Stack(
        children: [
          // Bottom shadow/depth (Solid, with outer drop shadow to pop from background)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: darkBase, // No opacity to avoid blending with dark background
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    offset: const Offset(0, 4),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
          // Main button
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFD59E), baseColor, Color(0xFFF7A23B)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    offset: const Offset(0, 3),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: const Color(0xFF3B2410),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      color: const Color(0xFF3B2410),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToDetails(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, anim, _) => FadeTransition(
          opacity: anim,
          child: DetailsPage(
            apiKey: widget.apiKey,
            base: widget.base,
            imgW185: widget.imgW185,
            imgW500: widget.imgW500,
            imgW780: widget.imgW780,
            id: widget.item.id,
            mediaType: widget.item.mediaType,
            linkApiBase: EnvConfig.luminoBackendUrl,
            primeboxUrl: widget.item.primeboxUrl,
            primeboxSubjectType: widget.item.primeboxSubjectType,
            primeboxType: widget.item.primeboxType,
            movieboxSubjectId: widget.item.movieboxSubjectId,
            initialTitle: widget.item.displayTitle,
            initialBackdrop: widget.item.backdropPath ?? widget.item.posterPath,
          ),
        ),
      ),
    ).then((_) => widget.onReturn?.call());
  }
}

class _ModernBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _ModernBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ModernDots extends StatelessWidget {
  final int count;
  final int index;
  const _ModernDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuart,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isActive
                ? const Color(0xFFFFB561)
                : Colors.white.withValues(alpha: 0.15),
          ),
        );
      }),
    );
  }
}

// ===================== Horizontal Section =====================

class _ModernHorizontalSection extends StatelessWidget {
  final String title;
  final List<TmdbItem> items;
  final String imgBase;
  final String apiKey;
  final String base;
  final String imgW185;
  final String imgW500;
  final String imgW780;
  final bool isDesktop;
  final VoidCallback? onReturn;

  const _ModernHorizontalSection({
    required this.title,
    required this.items,
    required this.imgBase,
    required this.apiKey,
    required this.base,
    required this.imgW185,
    required this.imgW500,
    required this.imgW780,
    required this.isDesktop,
    this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

    final double cardWidth = isDesktop
        ? 160.0
        : (isSmallScreen ? 115.0 : 130.0);
    final double cardHeight = cardWidth * 1.5 + (isSmallScreen ? 50 : 60);
    final displayItems = items.length > 20 ? items.sublist(0, 20) : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isSmallScreen ? 16 : 20,
            24,
            isSmallScreen ? 16 : 20,
            16,
          ),
          child: Row(
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 16 : 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: displayItems.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _ModernMediaCard(
              item: displayItems[i],
              width: cardWidth,
              apiKey: apiKey,
              base: base,
              imgW185: imgW185,
              imgW500: imgW500,
              imgW780: imgW780,
              onReturn: onReturn,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModernMediaCard extends StatelessWidget {
  final TmdbItem item;
  final double width;
  final String apiKey;
  final String base;
  final String imgW185;
  final String imgW500;
  final String imgW780;
  final VoidCallback? onReturn;

  const _ModernMediaCard({
    required this.item,
    required this.width,
    required this.apiKey,
    required this.base,
    required this.imgW185,
    required this.imgW500,
    required this.imgW780,
    this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final img = item.posterPath ?? item.backdropPath;
    final imageUrl = img != null
        ? (img.startsWith('http') ? img : '$imgW500$img')
        : null;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailsPage(
              apiKey: apiKey,
              base: base,
              imgW185: imgW185,
              imgW500: imgW500,
              imgW780: imgW780,
              id: item.id,
              mediaType: item.mediaType,
              linkApiBase: EnvConfig.luminoBackendUrl,
              primeboxUrl: item.primeboxUrl,
              primeboxSubjectType: item.primeboxSubjectType,
              primeboxType: item.primeboxType,
              movieboxSubjectId: item.movieboxSubjectId,
              initialTitle: item.displayTitle,
              initialBackdrop: item.backdropPath ?? item.posterPath,
            ),
          ),
        ).then((_) => onReturn?.call());
      },
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                              errorWidget: (context, url, error) =>
                                  Container(color: Colors.white10),
                            )
                          : Container(color: Colors.white10),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            item.mediaType == 'tv' ? 'TV' : 'MOVIE',
                            style: GoogleFonts.outfit(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.1),
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.yearLabel.isNotEmpty ? item.yearLabel : item.typeLabel,
              style: GoogleFonts.outfit(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== Loading & Error =====================

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box({double h = 160, double r = 18}) => Container(
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFF171C26),
        borderRadius: BorderRadius.circular(r),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const CircleAvatar(radius: 22, backgroundColor: Color(0xFF171C26)),
            const SizedBox(width: 12),
            Expanded(child: box(h: 40, r: 12)),
            const SizedBox(width: 12),
            const CircleAvatar(radius: 20, backgroundColor: Color(0xFF171C26)),
          ],
        ),
        const SizedBox(height: 18),
        box(h: 52, r: 14),
        const SizedBox(height: 18),
        box(h: 210, r: 20),
        const SizedBox(height: 20),
        box(h: 22, r: 8),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: Row(
            children: List.generate(
              3,
              (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: box(h: 240),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoNetworkState extends StatelessWidget {
  final VoidCallback onRetry;

  const _NoNetworkState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C0C0F),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF242633), Color(0xFF151822)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 26,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 36,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'No Internet Connection',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'Home content could not be loaded.\nCheck your network and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 26),
              FilledButton.tonal(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const MyDownloadsPage(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          const begin = Offset(0.0, 0.05);
                          const end = Offset.zero;
                          const curve = Curves.easeOutQuart;
                          var tween = Tween(
                            begin: begin,
                            end: end,
                          ).chain(CurveTween(curve: curve));
                          var offsetAnimation = animation.drive(tween);
                          var fadeAnimation = animation.drive(
                            CurveTween(curve: Curves.easeIn),
                          );

                          return FadeTransition(
                            opacity: fadeAnimation,
                            child: SlideTransition(
                              position: offsetAnimation,
                              child: child,
                            ),
                          );
                        },
                    transitionDuration: const Duration(milliseconds: 500),
                  ),
                ),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                icon: const Icon(Icons.download_for_offline_rounded),
                label: const Text('Go to Downloads'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Failed to load.\n$message', textAlign: TextAlign.center),
    );
  }
}

// ===================== Models =====================

class TmdbItem {
  final int id;
  final String? title;
  final String? name;
  final String? posterPath;
  final String? backdropPath;
  final String mediaType;
  final double? voteAverage;

  // NEW
  final String? releaseDate;
  final String? firstAirDate;

  // PRIMEBOX
  final String? primeboxUrl;
  final int? primeboxSubjectType;
  final String? primeboxType;
  final String? movieboxSubjectId;
  final String? overview;
  final List<int>? genreIds;
  final List<String>? genres;
  final String? logoPath;

  TmdbItem({
    required this.id,
    required this.mediaType,
    this.title,
    this.name,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
    this.releaseDate,
    this.firstAirDate,
    this.primeboxUrl,
    this.primeboxSubjectType,
    this.primeboxType,
    this.movieboxSubjectId,
    this.overview,
    this.genreIds,
    this.genres,
    this.logoPath,
  });

  String get displayTitle {
    final t = (title ?? name ?? '').trim();
    if (t.isEmpty) return 'Untitled-$hashCode';
    return t;
  }

  String get typeLabel {
    switch (mediaType) {
      case 'tv':
        return 'TV Show';
      case 'movie':
        return 'Movie';
      default:
        return mediaType.toUpperCase();
    }
  }

  // NEW: release year
  String get yearLabel {
    final raw = releaseDate ?? firstAirDate;
    if (raw == null || raw.isEmpty) return '';

    // TMDB format is usually "YYYY-MM-DD"
    if (raw.length >= 4) {
      final y = raw.substring(0, 4);
      if (RegExp(r'^\d{4}$').hasMatch(y)) return y;
    }
    return '';
  }

  factory TmdbItem.fromJson(Map<String, dynamic> json) {
    return TmdbItem(
      id: (json['id'] ?? 0) as int,
      title: json['title'] as String?,
      name: json['name'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      mediaType:
          (json['media_type'] as String?) ??
          (json.containsKey('first_air_date')
              ? 'tv'
              : json.containsKey('release_date')
              ? 'movie'
              : 'unknown'),
      voteAverage: (json['vote_average'] is num)
          ? (json['vote_average'] as num).toDouble()
          : null,
      // NEW:
      releaseDate: json['release_date'] as String?,
      firstAirDate: json['first_air_date'] as String?,
      movieboxSubjectId: json['movieboxSubjectId'] as String?,
      overview: json['overview'] as String?,
      genreIds: (json['genre_ids'] as List?)?.cast<int>(),
    );
  }
}

class _DateUtil {
  static String today() {
    final d = DateTime.now().toUtc();
    return _fmt(d);
  }

  static String lastWeekStart() {
    final now = DateTime.now().toUtc();
    final d = now.subtract(const Duration(days: 7));
    return _fmt(DateTime.utc(d.year, d.month, d.day));
  }

  static String nextWeek() {
    final now = DateTime.now().toUtc();
    final d = now.add(const Duration(days: 7));
    return _fmt(DateTime.utc(d.year, d.month, d.day));
  }

  static String _fmt(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
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
          'assets/animations/loader.json',
          repeat: true,
          errorBuilder: (context, error, stackTrace) {
            return const CircularProgressIndicator(color: Colors.cyan);
          },
        ),
      ),
    );
  }
}

// ===================== NEW: Check Update Screen =====================

class CheckUpdatePage extends StatefulWidget {
  const CheckUpdatePage({super.key});

  @override
  State<CheckUpdatePage> createState() => _CheckUpdatePageState();
}

class _CheckUpdatePageState extends State<CheckUpdatePage> {
  bool _loading = false;
  String _currentVersion = "...";

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _currentVersion = info.version);
      }
    } catch (e) {
      debugPrint("Error loading version: $e");
    }
  }

  Future<void> _handleCheckUpdate() async {
    setState(() => _loading = true);
    await UpdateService().checkForUpdatesNow(context);
    if (mounted) setState(() => _loading = false);
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            color: Colors.white,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Update Center',
          style: GoogleFonts.comme(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: const [ProfileButton(), SizedBox(width: 8)],
      ),
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(color: Color(0xFF0F0F0E)),
            ),
          ),
          // Radial Glow
          Positioned(
            top: -150,
            left: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    blurRadius: 120,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.05),
                    blurRadius: 120,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Modern Icon Illustration
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.05),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedDownload01,
                            size: 84,
                            color: Colors.orangeAccent,
                          ),
                          if (_loading)
                            SizedBox(
                              width: 120,
                              height: 120,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.primary.withValues(alpha: 0.3),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    // Title with Syne font
                    Text(
                      'System Update',
                      style: GoogleFonts.comme(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Keep your Lumino experience smooth and secure. Check for the latest improvements and features.',
                      textAlign: TextAlign.center,
                      style: theme.bodyLarge?.copyWith(
                        color: Colors.white54,
                        height: 1.6,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Glassmorphic Version Badge
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.orangeAccent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.orangeAccent,
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Current v$_currentVersion',
                                style: theme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 64),
                    // Premium Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: _loading
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.orangeAccent.withValues(alpha: 0.2),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                        ),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: _loading ? null : _handleCheckUpdate,
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.black,
                                  ),
                                )
                              : Text(
                                  'Check for Updates',
                                  style: GoogleFonts.syne(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Secondary Link
                    Opacity(
                      opacity: 0.5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedGlobal,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'lumino-app.web.app',
                            style: theme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModernUpdateDialog extends StatelessWidget {
  final String latestVersion;

  const _ModernUpdateDialog({required this.latestVersion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
            BoxShadow(
              color: Colors.orangeAccent.withValues(alpha: 0.05),
              blurRadius: 60,
              spreadRadius: -10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E1E1E).withValues(alpha: 0.9),
                    const Color(0xFF121212).withValues(alpha: 0.95),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Accent Bar
                    Container(
                      height: 4,
                      width: 60,
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                      child: Column(
                        children: [
                          // Modern Illustration
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                                ),
                              ),
                              const HugeIcon(
                                icon: HugeIcons.strokeRoundedDownload01,
                                size: 40,
                                color: Colors.orangeAccent,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Version Badge
                          Text(
                            'Update Available',
                            style: GoogleFonts.comme(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.orangeAccent.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              'v$latestVersion',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.orangeAccent,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'A new version is available',
                            textAlign: TextAlign.center,
                            style: theme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.5),
                              height: 1.6,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Primary Action
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orangeAccent,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                Navigator.pop(context);
                                final websiteUrl = Uri.parse(
                                  'https://sanjeevsnair.github.io/Lumino_window_Autoupdater/',
                                );
                                if (await canLaunchUrl(websiteUrl)) {
                                  await launchUrl(
                                    websiteUrl,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              child: Text(
                                'Update Now',
                                style: GoogleFonts.comme(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Secondary Action
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Remind me later',
                                style: theme.labelLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===================== Continue Watching Section =====================

class _ModernContinueWatching extends StatelessWidget {
  final List<WatchHistoryItem> items;
  final String apiKey;
  final String base;
  final String imgW185;
  final String imgW500;
  final String imgW780;
  final bool isDesktop;
  final VoidCallback onRefresh;

  const _ModernContinueWatching({
    required this.items,
    required this.apiKey,
    required this.base,
    required this.imgW185,
    required this.imgW500,
    required this.imgW780,
    required this.isDesktop,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final double cardWidth = isDesktop ? 280.0 : 190.0;
    final double cardHeight = cardWidth * 0.56 + 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Text(
            'Continue Watching',
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) => _ModernContinueCard(
              item: items[index],
              width: cardWidth,
              apiKey: apiKey,
              base: base,
              imgW185: imgW185,
              imgW500: imgW500,
              imgW780: imgW780,
              isDesktop: isDesktop,
              onRefresh: onRefresh,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModernContinueCard extends StatelessWidget {
  final WatchHistoryItem item;
  final double width;
  final String apiKey;
  final String base;
  final String imgW185;
  final String imgW500;
  final String imgW780;
  final bool isDesktop;
  final VoidCallback onRefresh;

  const _ModernContinueCard({
    required this.item,
    required this.width,
    required this.apiKey,
    required this.base,
    required this.imgW185,
    required this.imgW500,
    required this.imgW780,
    required this.isDesktop,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final poster = item.posterPath;
    final imageUrl = poster != null
        ? (poster.startsWith('http') ? poster : '$imgW780$poster')
        : null;
    final progress = (item.position / (item.duration > 0 ? item.duration : 1))
        .clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailsPage(
              apiKey: apiKey,
              base: base,
              imgW185: imgW185,
              imgW500: imgW500,
              imgW780: imgW780,
              id: item.id ?? 0,
              mediaType: item.mediaType,
              linkApiBase: EnvConfig.luminoBackendUrl,
              primeboxUrl: item.primeboxUrl,
              primeboxSubjectType: item.primeboxSubjectType,
              primeboxType: item.primeboxType,
              movieboxSubjectId: item.movieboxSubjectId,
              initialTitle: item.title,
              initialBackdrop: item.posterPath,
            ),
          ),
        ).then((_) => onRefresh());
      },
      onLongPress: () async {
        final confirm = await _showRemoveDialog(context);
        if (confirm == true) {
          await WatchHistoryService.removeFromHistory(
            item.mediaType,
            item.id != null && item.id != 0
                ? item.id
                : (item.primeboxUrl ?? item.title),
            isOffline: item.isOffline,
          );
          onRefresh();
        }
      },
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background Image
              imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: Colors.white.withValues(alpha: 0.05)),
                      errorWidget: (context, url, error) =>
                          Container(color: Colors.white10),
                    )
                  : Container(color: Colors.white10),

              // Glass Gradient Overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.2),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),

              // Play Icon (Subtle)
              Center(
                child: Container(
                  padding: EdgeInsets.all(isDesktop ? 10 : 8),
                  margin: EdgeInsets.only(bottom: isDesktop ? 0 : 15),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: isDesktop ? 32 : 24,
                  ),
                ),
              ),

              // Info Area (Bottom)
              Positioned(
                bottom: -6,
                left: 0,
                right: 0,
                child: ClipRect(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.3),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.mediaType == 'tv'
                              ? 'Season ${item.season} · Episode ${item.episode}'
                              : 'Continue Movie',
                          style: GoogleFonts.outfit(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Progress Bar (Integrated at the bottom)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  color: Colors.white.withValues(alpha: 0.1),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFB561), Color(0xFFFF8C1A)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Desktop Remove Button
              if (isDesktop)
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () async {
                      final confirm = await _showRemoveDialog(context);
                      if (confirm == true) {
                        await WatchHistoryService.removeFromHistory(
                          item.mediaType,
                          item.id != null && item.id != 0
                              ? item.id
                              : (item.primeboxUrl ?? item.title),
                          isOffline: item.isOffline,
                        );
                        onRefresh();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 14,
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

  Future<bool?> _showRemoveDialog(BuildContext context) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Remove History',
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
                    // Dynamic Glowing Delete Icon Container
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
                        Icons.delete_sweep_rounded,
                        size: 32,
                        color: Color(0xFFFF4949),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Dialog Header Title
                    const Text(
                      'Remove History?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Body text describing item to be removed
                    Text(
                      'Remove "${item.title}" from your watch history?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Modern Pill buttons layout
                    Row(
                      children: [
                        // Glassmorphic Cancel Button
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx, false),
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
                                'Cancel',
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

                        // Vibrant Solid Orange Gradient Delete Button
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx, true),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFB561),
                                    Color(0xFFFF8C1A),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFF8C1A,
                                    ).withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Remove',
                                style: TextStyle(
                                  color: Colors.black,
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
  }
}

class _ModernLiveTvPromo extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDesktop;

  const _ModernLiveTvPromo({required this.onTap, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

    // Dynamic scaling based on screen width
    final double horizontalPadding = isDesktop ? 40 : 20;
    final double cardHeight = isDesktop ? 160 : (isSmallScreen ? 110 : 130);
    final double iconSize = isDesktop ? 64 : (isSmallScreen ? 40 : 48);
    final double fontSizeTitle = isDesktop ? 22 : (isSmallScreen ? 14 : 16);
    final double fontSizeSub = isDesktop ? 14 : (isSmallScreen ? 11 : 12);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 24,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1E26), Color(0xFF0F0F13)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB561).withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned(
                  right: -20,
                  top: -20,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFB561).withValues(alpha: 0.1),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                  child: Row(
                    children: [
                      SizedBox(
                        width: iconSize,
                        height: iconSize,

                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedTv01,
                          color: const Color(0xFFFFB561),
                          size: iconSize * 0.5,
                        ),
                      ),
                      SizedBox(width: isSmallScreen ? 12 : 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Live TV Channels',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: fontSizeTitle,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Watch favorite channels in real-time.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: fontSizeSub,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: isSmallScreen ? 8 : 16),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 10 : 16,
                          vertical: isSmallScreen ? 8 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB561),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFB561).withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          'WATCH',
                          style: GoogleFonts.outfit(
                            color: Colors.black,
                            fontSize: isSmallScreen ? 10 : 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
