import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumino_app_moviestreaming/sync_service.dart';

class WatchHistoryItem {
  final int? id;
  final String title;
  final String? posterPath;
  final String mediaType; // 'movie' or 'tv'
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final int position; // in milliseconds
  final int duration; // in milliseconds
  final DateTime timestamp;
  final String? primeboxUrl;
  final int? primeboxSubjectType;
  final String? primeboxType;
  final String? movieboxSubjectId;
  final bool isOffline;

  WatchHistoryItem({
    this.id,
    required this.title,
    this.posterPath,
    required this.mediaType,
    this.season,
    this.episode,
    this.episodeTitle,
    required this.position,
    required this.duration,
    required this.timestamp,
    this.primeboxUrl,
    this.primeboxSubjectType,
    this.primeboxType,
    this.movieboxSubjectId,
    this.isOffline = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'posterPath': posterPath,
        'mediaType': mediaType,
        'season': season,
        'episode': episode,
        'episodeTitle': episodeTitle,
        'position': position,
        'duration': duration,
        'timestamp': timestamp.toIso8601String(),
        'primeboxUrl': primeboxUrl,
        'primeboxSubjectType': primeboxSubjectType,
        'primeboxType': primeboxType,
        'movieboxSubjectId': movieboxSubjectId,
        'isOffline': isOffline,
      };

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) => WatchHistoryItem(
        id: json['id'],
        title: json['title'],
        posterPath: json['posterPath'],
        mediaType: json['mediaType'],
        season: json['season'],
        episode: json['episode'],
        episodeTitle: json['episodeTitle'],
        position: json['position'],
        duration: json['duration'],
        timestamp: DateTime.parse(json['timestamp']),
        primeboxUrl: json['primeboxUrl'],
        primeboxSubjectType: json['primeboxSubjectType'],
        primeboxType: json['primeboxType'],
        movieboxSubjectId: json['movieboxSubjectId'],
        isOffline: json['isOffline'] ?? false,
      );

  String get uniqueId {
    // Last resort: Title
    final suffix = isOffline ? '_offline' : '_online';
    if (id != null && id != 0) {
      return '${mediaType}_id_$id$suffix';
    }
    if (primeboxUrl != null && primeboxUrl!.isNotEmpty) {
      return '${mediaType}_url_$primeboxUrl$suffix';
    }
    return '${mediaType}_title_$title$suffix';
  }
  }


class WatchHistoryService {
  static const String _key = 'watch_history';

  static Future<void> saveProgress({
    int? id,
    required String title,
    String? posterPath,
    required String mediaType,
    int? season,
    int? episode,
    String? episodeTitle,
    required int position,
    required int duration,
    String? primeboxUrl,
    int? primeboxSubjectType,
    String? primeboxType,
    String? movieboxSubjectId,
    bool isOffline = false,
  }) async {
    // Don't save if position is 0 or duration is 0
    if (duration <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final List<WatchHistoryItem> history = await getHistory();

    final newItem = WatchHistoryItem(
      id: id,
      title: title,
      posterPath: posterPath,
      mediaType: mediaType,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      position: position,
      duration: duration,
      timestamp: DateTime.now().toUtc(),
      primeboxUrl: primeboxUrl,
      primeboxSubjectType: primeboxSubjectType,
      primeboxType: primeboxType,
      movieboxSubjectId: movieboxSubjectId,
      isOffline: isOffline,
    );

    // Remove existing entry for the same movie/series
    history.removeWhere((item) => item.uniqueId == newItem.uniqueId);

    // Add new entry at the beginning
    history.insert(0, newItem);

    // Keep only last 20 items
    if (history.length > 20) {
      history.removeRange(20, history.length);
    }

    final List<String> encodedList = history.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList(_key, encodedList);
    SyncService.sync();
  }

  static Future<List<WatchHistoryItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? encodedList = prefs.getStringList(_key);
    if (encodedList == null) return [];

    try {
      return encodedList.map((e) => WatchHistoryItem.fromJson(json.decode(e))).toList();
    } catch (e) {
      debugPrint('Error parsing history: $e');
      return [];
    }
  }

  static Future<WatchHistoryItem?> getProgress(String mediaType, dynamic idOrTitleOrUrl, {bool isOffline = false}) async {
    final history = await getHistory();
    final String searchStr = idOrTitleOrUrl.toString();

    try {
      return history.firstWhere((item) {
        if (item.mediaType != mediaType) return false;
        if (item.isOffline != isOffline) return false;

        // Match by ID
        if (item.id != null && item.id.toString() == searchStr) return true;

        // Match by Primebox URL
        if (item.primeboxUrl != null && item.primeboxUrl == searchStr) return true;

        // Match by Title
        if (item.title == searchStr) return true;

        return false;
      });
    } catch (_) {
      return null;
    }
  }

  static Future<WatchHistoryItem?> getProgressByFullTitle(String fullTitle, {bool isOffline = false}) async {
    final history = await getHistory();

    // Check for exact match first (Movie case or simple Title)
    for (final it in history) {
      if (it.isOffline == isOffline && it.title == fullTitle) return it;
    }

    // Check for Series match "Title • S1E1"
    if (fullTitle.contains(' • S')) {
      final parts = fullTitle.split(' • S');
      final title = parts[0];
      final suffix = parts[1]; // "1E1"
      final epParts = suffix.split('E');
      if (epParts.length == 2) {
        final s = int.tryParse(epParts[0]);
        final e = int.tryParse(epParts[1]);
        for (final it in history) {
          if (it.isOffline == isOffline && it.title == title && it.season == s && it.episode == e) {
            return it;
          }
        }
      }
    }

    return null;
  }

  static Future<void> removeFromHistory(String mediaType, dynamic idOrTitleOrUrl, {bool isOffline = false}) async {
    // 1. Pull latest from cloud and merge to ensure we have the most up-to-date list
    await SyncService.syncCloudToLocal();

    // 2. Now perform the removal on the merged list
    final history = await getHistory();
    final String searchStr = idOrTitleOrUrl.toString();
    
    history.removeWhere((item) {
      if (item.mediaType != mediaType) return false;
      if (item.isOffline != isOffline) return false;
      
      if (item.id != null && item.id.toString() == searchStr) return true;
      if (item.primeboxUrl != null && item.primeboxUrl == searchStr) return true;
      if (item.title == searchStr) return true;
      return false;
    });
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, history.map((e) => jsonEncode(e.toJson())).toList());
    
    // 3. Push the state without the deleted item back to the cloud
    await SyncService.syncLocalToCloud();
  }
}
