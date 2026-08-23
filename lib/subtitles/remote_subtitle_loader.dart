import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RemoteSubtitle {
  final String language;
  final String url;

  RemoteSubtitle({required this.language, required this.url});
}

class RemoteSubtitleLoader {
  static const _movieApi = 'https://sub.vdrk.site/v1/movie';
  static const _tvApi = 'https://sub.vdrk.site/v1/tv';

  /// Entry point
  static Future<List<RemoteSubtitle>> load({
    required String tmdbId,
    int? season,
    int? episode,
  }) async {
    try {
      final String url;
      if (season != null && episode != null) {
        url = '$_tvApi/$tmdbId/$season/$episode';
      } else {
        url = '$_movieApi/$tmdbId';
      }

      debugPrint('[subtitles] Fetching from: $url');
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      
      if (res.statusCode != 200) {
        debugPrint('[subtitles] API error: ${res.statusCode}');
        return [];
      }

      final List data = jsonDecode(res.body);
      return data.map<RemoteSubtitle>((e) {
        return RemoteSubtitle(
          language: e['label'] ?? 'Unknown',
          url: e['file'] ?? '',
        );
      }).where((s) => s.url.isNotEmpty).toList();
    } catch (e) {
      debugPrint('[subtitles] Error loading subtitles: $e');
      return [];
    }
  }
}

