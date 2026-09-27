// ignore_for_file: unused_local_variable
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:lumino_app_moviestreaming/config/env_config.dart';

/// Base URL of the MovieBox API server
String get _movieboxBase => EnvConfig.lambdaUrl;

/// A single search result from /search
class MovieBoxItem {
  final String id; // subjectId (string)
  final String title;
  final String type; // 'movie' | 'series'
  final String? poster;
  final String? rating;
  final int? year;

  MovieBoxItem({
    required this.id,
    required this.title,
    required this.type,
    this.poster,
    this.rating,
    this.year,
  });

  String get yearLabel {
    if (year != null && year! > 0) return year.toString();
    final match = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(title);
    if (match != null) return match.group(0)!;
    return '';
  }

  String get displayTitle {
    final stripped = title
        .replaceAll(RegExp(r'\s*[\(\[]\s*(19\d{2}|20\d{2})\s*[\)\]]\s*$'), '')
        .trim();
    return stripped.isNotEmpty ? stripped : title;
  }

  factory MovieBoxItem.fromJson(Map<String, dynamic> json) {
    int? parsedYear;
    if (json['year'] is int) {
      parsedYear = json['year'] as int;
    } else if (json['year'] != null) {
      parsedYear = int.tryParse(json['year'].toString());
    } else if (json['release_date'] != null &&
        json['release_date'].toString().length >= 4) {
      parsedYear = int.tryParse(
        json['release_date'].toString().substring(0, 4),
      );
    } else if (json['releaseDate'] != null &&
        json['releaseDate'].toString().length >= 4) {
      parsedYear = int.tryParse(
        json['releaseDate'].toString().substring(0, 4),
      );
    } else if (json['first_air_date'] != null &&
        json['first_air_date'].toString().length >= 4) {
      parsedYear = int.tryParse(
        json['first_air_date'].toString().substring(0, 4),
      );
    } else if (json['pub_date'] != null &&
        json['pub_date'].toString().length >= 4) {
      parsedYear = int.tryParse(
        json['pub_date'].toString().substring(0, 4),
      );
    } else if (json['date'] != null &&
        json['date'].toString().length >= 4) {
      parsedYear = int.tryParse(
        json['date'].toString().substring(0, 4),
      );
    }

    return MovieBoxItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown',
      type: json['type']?.toString() ?? 'movie',
      poster: json['poster']?.toString(),
      rating: json['rating']?.toString(),
      year: parsedYear,
    );
  }

  bool get isMovie => type.toLowerCase() != 'series';
}

/// Recommended / similar title from /details
class MovieBoxRecommendation {
  final String id;
  final String title;
  final String type; // 'movie' | 'series'
  final String? poster;
  final String? rating;
  final int? year;

  MovieBoxRecommendation({
    required this.id,
    required this.title,
    required this.type,
    this.poster,
    this.rating,
    this.year,
  });

  bool get isMovie =>
      type.toLowerCase() != 'series' && type.toLowerCase() != 'tv';

  String get yearLabel => year != null ? year.toString() : '';

  String get ratingLabel {
    if (rating == null || rating!.isEmpty) return '';
    final d = double.tryParse(rating!);
    if (d != null && d > 0) return d.toStringAsFixed(1);
    return rating!;
  }

  factory MovieBoxRecommendation.fromJson(Map<String, dynamic> json) {
    int? parsedYear;
    if (json['year'] is int) {
      parsedYear = json['year'] as int;
    } else if (json['year'] != null) {
      parsedYear = int.tryParse(json['year'].toString());
    } else if (json['release_date'] != null &&
        json['release_date'].toString().length >= 4) {
      parsedYear = int.tryParse(
        json['release_date'].toString().substring(0, 4),
      );
    } else if (json['first_air_date'] != null &&
        json['first_air_date'].toString().length >= 4) {
      parsedYear = int.tryParse(
        json['first_air_date'].toString().substring(0, 4),
      );
    }

    final rawRating = json['rating'] ?? json['vote_average'];
    String? parsedRating;
    if (rawRating != null) {
      final d = double.tryParse(rawRating.toString());
      if (d != null && d > 0) {
        parsedRating = d.toStringAsFixed(1);
      } else {
        parsedRating = rawRating.toString();
      }
    }

    final posterVal = json['poster'] ?? json['poster_path'];

    return MovieBoxRecommendation(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? 'Unknown',
      type:
          (json['type']?.toString().toLowerCase() == 'series' ||
              json['type']?.toString().toLowerCase() == 'tv')
          ? 'series'
          : 'movie',
      poster: posterVal?.toString(),
      rating: parsedRating,
      year: parsedYear,
    );
  }
}

/// Full details bundle from /details
class MovieBoxDetails {
  final String id;
  final String title;
  final String type; // 'movie' | 'series'
  final int? year;
  final int? duration; // minutes
  final List<String> genre;
  final String? plot;
  final String? poster;
  final String? background;
  final String? logo;
  final String? imdbId;
  final int? tmdbId;
  final String? rating;
  final List<Map<String, dynamic>> actors;
  final List<MovieBoxEpisode> episodes; // only for series
  final List<MovieBoxRecommendation> recommendations;

  final String? airingStatus;
  final MovieBoxEpisodeInfo? nextEpisode;
  final MovieBoxEpisodeInfo? lastEpisode;
  final bool? inProduction;
  final int? totalSeasons;
  final int? totalEpisodes;

  MovieBoxDetails({
    required this.id,
    required this.title,
    required this.type,
    this.year,
    this.duration,
    required this.genre,
    this.plot,
    this.poster,
    this.background,
    this.logo,
    this.imdbId,
    this.tmdbId,
    this.rating,
    required this.actors,
    required this.episodes,
    this.recommendations = const [],
    this.airingStatus,
    this.nextEpisode,
    this.lastEpisode,
    this.inProduction,
    this.totalSeasons,
    this.totalEpisodes,
  });

  bool get isMovie => type.toLowerCase() != 'series';

  factory MovieBoxDetails.fromJson(Map<String, dynamic> json) {
    final rawGenre = json['genre'];
    List<String> genres = [];
    if (rawGenre is List) {
      genres = rawGenre.map((e) => e.toString()).toList();
    } else if (rawGenre is String) {
      genres = rawGenre
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final rawActors = json['actors'];
    List<Map<String, dynamic>> actors = [];
    if (rawActors is List) {
      for (final a in rawActors) {
        if (a is Map) actors.add(Map<String, dynamic>.from(a));
      }
    }

    final rawEpisodes = json['episodes'];
    List<MovieBoxEpisode> episodes = [];
    if (rawEpisodes is List) {
      for (final e in rawEpisodes) {
        if (e is Map) {
          try {
            episodes.add(
              MovieBoxEpisode.fromJson(Map<String, dynamic>.from(e)),
            );
          } catch (_) {}
        }
      }
    }

    final rawRecs = json['recommendations'];
    List<MovieBoxRecommendation> recommendations = [];
    final currentId = json['id']?.toString().trim() ?? '';
    final currentTitleNorm = json['title'] != null
        ? json['title'].toString().toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9]'),
            '',
          )
        : '';
    final seenIds = <String>{if (currentId.isNotEmpty) currentId};
    final seenTitles = <String>{
      if (currentTitleNorm.isNotEmpty) currentTitleNorm,
    };

    if (rawRecs is List) {
      for (final r in rawRecs) {
        if (r is Map) {
          try {
            final rec = MovieBoxRecommendation.fromJson(
              Map<String, dynamic>.from(r),
            );
            final recId = rec.id.trim();
            final recTitleNorm = rec.title.toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            );

            // Exclude currently opened movie/series and deduplicate
            if (recId.isNotEmpty && seenIds.contains(recId)) continue;
            if (recTitleNorm.isNotEmpty && seenTitles.contains(recTitleNorm))
              continue;

            if (recId.isNotEmpty) seenIds.add(recId);
            if (recTitleNorm.isNotEmpty) seenTitles.add(recTitleNorm);
            recommendations.add(rec);
          } catch (_) {}
        }
      }
    }

    return MovieBoxDetails(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown',
      type: json['type']?.toString() ?? 'movie',
      year: json['year'] is int
          ? json['year']
          : int.tryParse(json['year']?.toString() ?? ''),
      duration: json['duration'] is int
          ? json['duration']
          : int.tryParse(
              json['duration']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ??
                  '',
            ),
      genre: genres,
      plot: json['plot']?.toString(),
      poster: json['poster']?.toString(),
      background: json['background']?.toString(),
      logo: json['logo']?.toString(),
      imdbId: json['imdb_id']?.toString(),
      tmdbId: json['tmdb_id'] is int
          ? json['tmdb_id']
          : int.tryParse(json['tmdb_id']?.toString() ?? ''),
      rating: json['rating']?.toString(),
      actors: actors,
      episodes: episodes,
      recommendations: recommendations,
      airingStatus: json['airing_status']?.toString(),
      nextEpisode: json['next_episode'] != null
          ? MovieBoxEpisodeInfo.fromJson(
              Map<String, dynamic>.from(json['next_episode']),
            )
          : null,
      lastEpisode: json['last_episode'] != null
          ? MovieBoxEpisodeInfo.fromJson(
              Map<String, dynamic>.from(json['last_episode']),
            )
          : null,
      inProduction: json['in_production'] as bool?,
      totalSeasons: json['total_seasons'] as int?,
      totalEpisodes: json['total_episodes'] as int?,
    );
  }
}

class MovieBoxEpisode {
  /// Format: "subjectId|season|episode"
  final String data;
  final int season;
  final int episode;
  final String title;
  final String? description;
  final String? thumbnail;
  final String? aired;
  final int? runtime;

  MovieBoxEpisode({
    required this.data,
    required this.season,
    required this.episode,
    required this.title,
    this.description,
    this.thumbnail,
    this.aired,
    this.runtime,
  });

  factory MovieBoxEpisode.fromJson(Map<String, dynamic> json) {
    return MovieBoxEpisode(
      data: json['data']?.toString() ?? '',
      season: json['season'] is int
          ? json['season']
          : int.tryParse(json['season']?.toString() ?? '') ?? 1,
      episode: json['episode'] is int
          ? json['episode']
          : int.tryParse(json['episode']?.toString() ?? '') ?? 1,
      title: json['title']?.toString() ?? 'Episode',
      description: json['description']?.toString(),
      thumbnail: json['thumbnail']?.toString(),
      aired: json['aired']?.toString(),
      runtime: json['runtime'] is int
          ? json['runtime']
          : int.tryParse(
              json['runtime']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ??
                  '',
            ),
    );
  }
}

class MovieBoxEpisodeInfo {
  final int season;
  final int episode;
  final String title;
  final String? airDate;

  MovieBoxEpisodeInfo({
    required this.season,
    required this.episode,
    required this.title,
    this.airDate,
  });

  factory MovieBoxEpisodeInfo.fromJson(Map<String, dynamic> json) {
    return MovieBoxEpisodeInfo(
      season: json['season'] is int
          ? json['season']
          : int.tryParse(json['season']?.toString() ?? '') ?? 1,
      episode: json['episode'] is int
          ? json['episode']
          : int.tryParse(json['episode']?.toString() ?? '') ?? 1,
      title: json['title']?.toString() ?? 'Unknown',
      airDate: json['air_date']?.toString(),
    );
  }
}

/// A playable stream from /links
class MovieBoxStream {
  final String source; // e.g. "MovieBox Original Audio"
  final String name;
  final String url;
  final String type; // 'dash' | 'hls' | 'video' | 'auto' | 'magnet' | 'torrent'
  final int? quality; // numeric: 1080, 720, etc.
  final String? language; // Audio language label
  final Map<String, String> headers;
  final String? codec; // e.g. 'h264', 'hevc'
  final String serverTag; // 'Alpha' or 'Beta' — identifies the source server

  MovieBoxStream({
    required this.source,
    required this.name,
    required this.url,
    required this.type,
    this.quality,
    this.language,
    this.headers = const {},
    this.codec,
    this.serverTag = 'Alpha',
  });

  String get qualityLabel {
    if (quality != null && quality! > 0) {
      if (quality == 2160) return '4K';
      return '${quality}P';
    }
    final search = '$name $source'.toLowerCase();
    if (search.contains('2160p') ||
        search.contains('4k') ||
        search.contains('uhd'))
      return '4K';
    if (search.contains('1440p') || search.contains('2k')) return '1440P';
    if (search.contains('1080p') || search.contains('fhd')) return '1080P';
    if (search.contains('720p') || search.contains('hd')) return '720P';
    if (search.contains('480p') || search.contains('sd')) return '480P';
    if (search.contains('360p')) return '360P';
    return '1080P';
  }

  factory MovieBoxStream.fromJson(
    Map<String, dynamic> json, {
    String serverTag = 'Alpha',
  }) {
    final rawHeaders = json['headers'];
    Map<String, String> headers = {};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        headers[k.toString()] = v.toString();
      });
    }
    final rawQuality = json['quality'];
    int? quality;
    if (rawQuality is int) {
      quality = rawQuality;
    } else if (rawQuality != null) {
      final digits = rawQuality.toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) quality = int.tryParse(digits);
    }
    return MovieBoxStream(
      source: json['source']?.toString() ?? 'MovieBox',
      name: json['name']?.toString() ?? 'Stream',
      url: json['url']?.toString() ?? '',
      type: json['type']?.toString() ?? 'auto',
      quality: quality,
      language: json['language']?.toString(),
      headers: headers,
      codec: json['codec']?.toString(),
      serverTag: serverTag,
    );
  }
}

/// A subtitle entry from /links
class MovieBoxSubtitle {
  final String url;
  final String lang;

  MovieBoxSubtitle({required this.url, required this.lang});

  factory MovieBoxSubtitle.fromJson(Map<String, dynamic> json) {
    return MovieBoxSubtitle(
      url: json['url']?.toString() ?? '',
      lang: json['lang']?.toString() ?? 'Unknown',
    );
  }
}

class MovieBoxService {
  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  /// Search for movies/series. Returns a list of [MovieBoxItem].
  static Future<List<MovieBoxItem>> search(String query) async {
    final q = Uri.encodeQueryComponent(query.trim());
    try {
      final res = await http
          .get(Uri.parse('$_movieboxBase/search?q=$q'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = data['results'] as List? ?? [];
        return results
            .map((m) => MovieBoxItem.fromJson(m as Map<String, dynamic>))
            .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
            .toList();
      }
    } catch (e) {
      if (kDebugMode) print('[MovieBox] search error: $e');
    }
    return [];
  }

  /// Get full details for a subject by its ID. Returns [MovieBoxDetails] or null.
  static Future<MovieBoxDetails?> getDetails(String subjectId) async {
    try {
      final res = await http
          .get(
            Uri.parse('$_movieboxBase/details?id=$subjectId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return MovieBoxDetails.fromJson(data as Map<String, dynamic>);
      }
    } catch (e) {
      if (kDebugMode) print('[MovieBox] details error: $e');
    }
    return null;
  }

  /// Get playable links.
  /// [data] is: subjectId for movies, or "subjectId|season|episode" for series.
  static Future<
    ({List<MovieBoxStream> streams, List<MovieBoxSubtitle> subtitles})
  >
  getLinks(String data, {String host = 'https://api3.aoneroom.com'}) async {
    try {
      final encodedData = Uri.encodeQueryComponent(data);
      final encodedHost = Uri.encodeQueryComponent(host);
      final res = await http
          .get(
            Uri.parse(
              '$_movieboxBase/links?data=$encodedData&host=$encodedHost',
            ),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final body = json.decode(res.body);

        // ── Alpha Server streams (top-level) ──
        final rawStreams = body['streams'] as List? ?? [];
        final rawSubs = body['subtitles'] as List? ?? [];

        final streams = rawStreams
            .map(
              (s) => MovieBoxStream.fromJson(
                s as Map<String, dynamic>,
                serverTag: 'Alpha',
              ),
            )
            .where((s) => s.url.isNotEmpty)
            .toList();

        final subtitles = rawSubs
            .map((s) => MovieBoxSubtitle.fromJson(s as Map<String, dynamic>))
            .where((s) => s.url.isNotEmpty)
            .toList();

        // ── Beta Server streams (nested under 'betaserver') ──
        final betaServer = body['betaserver'];
        if (betaServer is Map) {
          final betaRawStreams = betaServer['streams'] as List? ?? [];
          final betaRawSubs = betaServer['subtitles'] as List? ?? [];

          final betaStreams = betaRawStreams
              .map(
                (s) => MovieBoxStream.fromJson(
                  s as Map<String, dynamic>,
                  serverTag: 'Beta',
                ),
              )
              .where((s) => s.url.isNotEmpty)
              .toList();

          streams.addAll(betaStreams);

          final betaSubs = betaRawSubs
              .map((s) => MovieBoxSubtitle.fromJson(s as Map<String, dynamic>))
              .where((s) => s.url.isNotEmpty)
              .toList();

          // Merge beta subtitles (avoid duplicates by URL)
          final existingUrls = subtitles.map((s) => s.url).toSet();
          for (final bs in betaSubs) {
            if (!existingUrls.contains(bs.url)) {
              subtitles.add(bs);
            }
          }

          if (kDebugMode)
            print(
              '[MovieBox] BetaServer: ${betaStreams.length} streams, ${betaSubs.length} subtitles',
            );
        }

        return (streams: streams, subtitles: subtitles);
      }
    } catch (e) {
      if (kDebugMode) print('[MovieBox] links error: $e');
    }
    return (streams: <MovieBoxStream>[], subtitles: <MovieBoxSubtitle>[]);
  }

  static int getLanguageRank(String str) {
    final lower = str.toLowerCase();
    if (lower.contains('original')) return 0;
    if (lower.contains('malayalam') || lower.contains('mal')) return 1;
    if (lower.contains('tamil') || lower.contains('tam')) return 2;
    if (lower.contains('hindi') || lower.contains('hin')) return 3;
    if (lower.contains('telugu') || lower.contains('tel')) return 4;
    if (lower.contains('kannada') || lower.contains('kan')) return 5;
    if (lower.contains('english') || lower.contains('eng')) return 6;
    if (lower.contains('spanish') ||
        lower.contains('esla') ||
        lower.contains('spa'))
      return 7;
    if (lower.contains('french') ||
        lower.contains('fra') ||
        lower.contains('fre'))
      return 8;
    if (lower.contains('portuguese') ||
        lower.contains('ptbr') ||
        lower.contains('por'))
      return 9;
    return 100;
  }

  /// Convert stream list into a httpSources map (quality → language → url)
  /// and an httpMetadata map (sourceId → {headers, url, type}) for the video player.
  static ({
    Map<String, Map<String, String>> httpSources,
    Map<String, dynamic> httpMetadata,
  })
  buildSourceMaps(List<MovieBoxStream> streams) {
    final httpSources = <String, Map<String, String>>{};
    final httpMetadata = <String, dynamic>{};

    // Sort streams according to language priority
    final sortedStreams = List<MovieBoxStream>.from(streams)
      ..sort((a, b) {
        final rankA = getLanguageRank(a.language ?? a.source);
        final rankB = getLanguageRank(b.language ?? b.source);
        if (rankA != rankB) return rankA.compareTo(rankB);
        return (a.language ?? a.source).compareTo(b.language ?? b.source);
      });

    const defaultHeaders = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': '*/*',
    };

    for (final stream in sortedStreams) {
      final quality = stream.qualityLabel;
      String lang = _sanitizeLang(stream.language ?? stream.source);

      // Append server tag to create unique provider keys per server
      // e.g. "English (Alpha)" vs "English (Beta)"
      final providerKey = '$lang (${stream.serverTag})';

      // For HLS streams that don't end in .m3u8 (e.g. BetaServer streamguide.cfd),
      // appending '#.m3u8' allows mobile media_kit (libmpv / FFmpeg) and desktop players
      // to identify the playlist format immediately and disables extension-picky checks
      // on raw fMP4 segment URLs, while preserving the clean URL sent over HTTP.
      String playableUrl = stream.url;
      if (stream.type.toLowerCase() == 'hls' &&
          !playableUrl.contains('.m3u8') &&
          !playableUrl.contains('.mpd')) {
        playableUrl = playableUrl.contains('#')
            ? playableUrl
            : '$playableUrl#.m3u8';
      }

      httpSources.putIfAbsent(quality, () => <String, String>{});
      httpSources[quality]![providerKey] = playableUrl;

      final sourceId = 'http|$quality|$providerKey';
      final streamHeaders = Map<String, String>.from(defaultHeaders)
        ..addAll(stream.headers);

      httpMetadata[sourceId] = {
        'url': playableUrl,
        'rawUrl': stream.url,
        'type': stream.type,
        'headers': streamHeaders,
        'language': lang,
        'quality': quality,
        'serverTag': stream.serverTag,
        'codec': stream.codec,
      };
    }

    return (httpSources: httpSources, httpMetadata: httpMetadata);
  }

  /// Convert subtitle list into the format expected by VideoPlayerScreen:
  /// { "English (Original Audio)": ["https://..."] }
  static Map<String, List<String>> buildSubtitleMap(
    List<MovieBoxSubtitle> subtitles,
  ) {
    final sortedSubtitles = List<MovieBoxSubtitle>.from(subtitles)
      ..sort((a, b) {
        final rankA = getLanguageRank(a.lang);
        final rankB = getLanguageRank(b.lang);
        if (rankA != rankB) return rankA.compareTo(rankB);
        return a.lang.compareTo(b.lang);
      });

    final out = <String, List<String>>{};
    for (final sub in sortedSubtitles) {
      if (sub.url.isNotEmpty) {
        out.putIfAbsent(sub.lang, () => []).add(sub.url);
      }
    }
    return out;
  }

  static String _sanitizeLang(String raw) {
    // Trim and clean for use as provider label
    return raw
        .replaceAll('Audio', '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
