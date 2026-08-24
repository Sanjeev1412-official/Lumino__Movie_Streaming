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

  MovieBoxItem({
    required this.id,
    required this.title,
    required this.type,
    this.poster,
    this.rating,
  });

  factory MovieBoxItem.fromJson(Map<String, dynamic> json) {
    return MovieBoxItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown',
      type: json['type']?.toString() ?? 'movie',
      poster: json['poster']?.toString(),
      rating: json['rating']?.toString(),
    );
  }

  bool get isMovie => type.toLowerCase() != 'series';
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
      genres = rawGenre.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
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
            episodes.add(MovieBoxEpisode.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      }
    }

    return MovieBoxDetails(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown',
      type: json['type']?.toString() ?? 'movie',
      year: json['year'] is int ? json['year'] : int.tryParse(json['year']?.toString() ?? ''),
      duration: json['duration'] is int ? json['duration'] : int.tryParse(json['duration']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? ''),
      genre: genres,
      plot: json['plot']?.toString(),
      poster: json['poster']?.toString(),
      background: json['background']?.toString(),
      logo: json['logo']?.toString(),
      imdbId: json['imdb_id']?.toString(),
      tmdbId: json['tmdb_id'] is int ? json['tmdb_id'] : int.tryParse(json['tmdb_id']?.toString() ?? ''),
      rating: json['rating']?.toString(),
      actors: actors,
      episodes: episodes,
      airingStatus: json['airing_status']?.toString(),
      nextEpisode: json['next_episode'] != null ? MovieBoxEpisodeInfo.fromJson(Map<String, dynamic>.from(json['next_episode'])) : null,
      lastEpisode: json['last_episode'] != null ? MovieBoxEpisodeInfo.fromJson(Map<String, dynamic>.from(json['last_episode'])) : null,
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
      season: json['season'] is int ? json['season'] : int.tryParse(json['season']?.toString() ?? '') ?? 1,
      episode: json['episode'] is int ? json['episode'] : int.tryParse(json['episode']?.toString() ?? '') ?? 1,
      title: json['title']?.toString() ?? 'Episode',
      description: json['description']?.toString(),
      thumbnail: json['thumbnail']?.toString(),
      aired: json['aired']?.toString(),
      runtime: json['runtime'] is int ? json['runtime'] : int.tryParse(json['runtime']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? ''),
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
      season: json['season'] is int ? json['season'] : int.tryParse(json['season']?.toString() ?? '') ?? 1,
      episode: json['episode'] is int ? json['episode'] : int.tryParse(json['episode']?.toString() ?? '') ?? 1,
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

  MovieBoxStream({
    required this.source,
    required this.name,
    required this.url,
    required this.type,
    this.quality,
    this.language,
    this.headers = const {},
  });

  String get qualityLabel {
    if (quality != null && quality! > 0) {
      if (quality == 2160) return '4K';
      return '${quality}P';
    }
    final search = '$name $url $source'.toLowerCase();
    if (search.contains('2160p') || search.contains('4k') || search.contains('uhd')) return '4K';
    if (search.contains('1440p') || search.contains('2k')) return '1440P';
    if (search.contains('1080p') || search.contains('fhd')) return '1080P';
    if (search.contains('720p') || search.contains('hd')) return '720P';
    if (search.contains('480p') || search.contains('sd')) return '480P';
    if (search.contains('360p')) return '360P';
    return '1080P';
  }

  factory MovieBoxStream.fromJson(Map<String, dynamic> json) {
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
      quality = int.tryParse(rawQuality.toString());
    }
    return MovieBoxStream(
      source: json['source']?.toString() ?? 'MovieBox',
      name: json['name']?.toString() ?? 'Stream',
      url: json['url']?.toString() ?? '',
      type: json['type']?.toString() ?? 'auto',
      quality: quality,
      language: json['language']?.toString(),
      headers: headers,
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
          .get(Uri.parse('$_movieboxBase/search?query=$q'), headers: _headers)
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
          .get(Uri.parse('$_movieboxBase/details?id=$subjectId'), headers: _headers)
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
  static Future<({List<MovieBoxStream> streams, List<MovieBoxSubtitle> subtitles})> getLinks(
    String data, {
    String host = 'https://api3.aoneroom.com',
  }) async {
    try {
      final encodedData = Uri.encodeQueryComponent(data);
      final encodedHost = Uri.encodeQueryComponent(host);
      final res = await http
          .get(Uri.parse('$_movieboxBase/links?data=$encodedData&host=$encodedHost'), headers: _headers)
          .timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        final rawStreams = body['streams'] as List? ?? [];
        final rawSubs = body['subtitles'] as List? ?? [];

        final streams = rawStreams
            .map((s) => MovieBoxStream.fromJson(s as Map<String, dynamic>))
            .where((s) => s.url.isNotEmpty)
            .toList();

        final subtitles = rawSubs
            .map((s) => MovieBoxSubtitle.fromJson(s as Map<String, dynamic>))
            .where((s) => s.url.isNotEmpty)
            .toList();

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
    if (lower.contains('spanish') || lower.contains('esla') || lower.contains('spa')) return 7;
    if (lower.contains('french') || lower.contains('fra') || lower.contains('fre')) return 8;
    if (lower.contains('portuguese') || lower.contains('ptbr') || lower.contains('por')) return 9;
    return 100;
  }

  /// Convert stream list into a httpSources map (quality → language → url)
  /// and an httpMetadata map (sourceId → {headers, url, type}) for the video player.
  static ({
    Map<String, Map<String, String>> httpSources,
    Map<String, dynamic> httpMetadata,
  }) buildSourceMaps(List<MovieBoxStream> streams) {
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

    for (final stream in sortedStreams) {
      final quality = stream.qualityLabel;
      String lang = _sanitizeLang(stream.language ?? stream.source);

      httpSources.putIfAbsent(quality, () => <String, String>{});
      httpSources[quality]![lang] = stream.url;

      final sourceId = 'http|$quality|$lang';
      httpMetadata[sourceId] = {
        'url': stream.url,
        'type': stream.type,
        'headers': stream.headers,
        'language': lang,
        'quality': quality,
      };
    }

    return (httpSources: httpSources, httpMetadata: httpMetadata);
  }

  /// Convert subtitle list into the format expected by VideoPlayerScreen:
  /// { "English (Original Audio)": ["https://..."] }
  static Map<String, List<String>> buildSubtitleMap(List<MovieBoxSubtitle> subtitles) {
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
    return raw.replaceAll('Audio', '').trim().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
