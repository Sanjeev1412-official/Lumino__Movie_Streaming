import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lumino_app_moviestreaming/watch_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncService {
  static final SupabaseClient _client = Supabase.instance.client;
  static bool _isRealtimeEnabled = false;
  static RealtimeChannel? _realtimeChannel;
  static final StreamController<void> onSyncNotify = StreamController.broadcast();

  /// Starts listening for realtime updates from Supabase.
  static void startRealtimeSync() {
    final user = _client.auth.currentUser;
    if (user == null || _isRealtimeEnabled) {
      debugPrint('Sync: Start ignored. User: ${user?.id}, Enabled: $_isRealtimeEnabled');
      return;
    }

    _isRealtimeEnabled = true;
    debugPrint('Sync: Starting Realtime Channel for user: ${user.id}');

    try {
      _realtimeChannel = _client.channel('public:user_sync_data:${user.id}');
      
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'user_sync_data',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: user.id,
        ),
        callback: (payload) {
          debugPrint('Sync: Realtime change detected via PostgresChanges! Event: ${payload.eventType}');
          syncCloudToLocal();
        },
      ).subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('Sync: Successfully subscribed to realtime changes.');
        } else if (status == RealtimeSubscribeStatus.channelError) {
          _isRealtimeEnabled = false;
          debugPrint('Sync: Realtime channel error: $error');
        } else if (status == RealtimeSubscribeStatus.timedOut) {
          debugPrint('Sync: Realtime subscription timed out.');
        }
      });
    } catch (e) {
      _isRealtimeEnabled = false;
      debugPrint('Sync: Error setting up realtime channel: $e');
    }
  }

  /// Stops the realtime listener.
  static void stopRealtimeSync() {
    if (_realtimeChannel != null) {
      _client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
    _isRealtimeEnabled = false;
    debugPrint('Sync: Stopped Realtime Listener.');
  }

  /// Full sync: Pull from cloud, merge, then Push back to cloud.
  /// Use this when saving progress to ensure no data is lost from other devices.
  static Future<void> sync() async {
    debugPrint('Sync: Starting full sync (Pull-Merge-Push)...');
    final success = await syncCloudToLocal();
    // If pull failed, don't push immediately to avoid overwriting cloud with potentially stale local data
    if (success) {
      await syncLocalToCloud();
    }
  }

  /// Syncs local data (history) to the cloud.
  static Future<void> syncLocalToCloud() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final historyList = prefs.getStringList('watch_history') ?? [];

      debugPrint('Sync: Pushing ${historyList.length} items to cloud...');
      
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        try {
          await _client.from('user_sync_data').upsert({
            'id': user.id,
            'watch_history': historyList.map((e) => json.decode(e)).toList(),
            'full_name': user.userMetadata?['full_name'],
            'avatar_url': user.userMetadata?['avatar_url'],
            'updated_at': now,
          });
          debugPrint('Sync: Successfully synced local data and profile to cloud table.');
        } catch (e) {
          debugPrint('Sync: Table upsert with updated_at failed, trying without it: $e');
          await _client.from('user_sync_data').upsert({
            'id': user.id,
            'watch_history': historyList.map((e) => json.decode(e)).toList(),
          });
          debugPrint('Sync: Successfully synced local data to cloud table (without updated_at).');
          // Still update metadata so we have a timestamp for deletion logic
          await _client.auth.updateUser(UserAttributes(data: {
            'sync_updated_at': now,
          }));
        }
      } catch (e) {
        debugPrint('Sync: All table upsert attempts failed, using metadata fallback: $e');
        final now = DateTime.now().toUtc().toIso8601String();
        await _client.auth.updateUser(UserAttributes(data: {
          'sync_watch_history': historyList,
          'sync_updated_at': now,
        }));
        debugPrint('Sync: Successfully synced local data to user metadata.');
      }
    } catch (e) {
      debugPrint('Sync: Failed to sync local to cloud: $e');
    }
  }

  /// Syncs cloud data to local storage.
  static Future<bool> syncCloudToLocal() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      debugPrint('Sync: Pulling data from cloud...');
      List<dynamic>? cloudHistory;
      DateTime cloudUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0);

      try {
        final response = await _client.from('user_sync_data').select('watch_history, updated_at, full_name, avatar_url').eq('id', user.id).maybeSingle();
        if (response != null) {
          cloudHistory = response['watch_history'];
          if (response['updated_at'] != null) {
            cloudUpdatedAt = DateTime.parse(response['updated_at']).toUtc();
          }
          
          // Sync profile metadata if it exists and is different
          final String? cloudName = response['full_name'];
          final String? cloudAvatar = response['avatar_url'];
          if (cloudName != null || cloudAvatar != null) {
            final currentName = user.userMetadata?['full_name'];
            final currentAvatar = user.userMetadata?['avatar_url'];
            
            if (cloudName != currentName || cloudAvatar != currentAvatar) {
              debugPrint('Sync: Profile change detected in cloud, applying to user metadata...');
              // Update the user metadata so it persists in the Auth system
              await Supabase.instance.client.auth.updateUser(
                UserAttributes(data: {
                  'full_name': ?cloudName,
                  'avatar_url': ?cloudAvatar,
                })
              );
            }
          }
          
          debugPrint('Sync: Found cloud history (table) with ${cloudHistory?.length} items, updated at $cloudUpdatedAt');
        }
      } catch (e) {
        debugPrint('Sync: Table select failed: $e');
      }

      if (cloudHistory == null) {
        debugPrint('Sync: Checking metadata fallback...');
        cloudHistory = user.userMetadata?['sync_watch_history'];
        final metaUpdated = user.userMetadata?['sync_updated_at'];
        if (metaUpdated != null) {
          cloudUpdatedAt = DateTime.parse(metaUpdated).toUtc();
        }
        debugPrint('Sync: Found cloud history (metadata) with ${cloudHistory?.length} items, updated at $cloudUpdatedAt');
      }

      final prefs = await SharedPreferences.getInstance();
      
      // Merge History
      if (cloudHistory != null) {
        final localHistory = prefs.getStringList('watch_history') ?? [];
        List<String> normalizedCloud = [];
        for (var item in cloudHistory) {
          normalizedCloud.add(item is String ? item : json.encode(item));
        }
        
        final mergedHistory = _mergeHistory(localHistory, normalizedCloud, cloudUpdatedAt);
        
        // Only update and notify if there's a change to avoid loops
        if (mergedHistory.length != localHistory.length || _listEquals(mergedHistory, localHistory) == false) {
          await prefs.setStringList('watch_history', mergedHistory);
          onSyncNotify.add(null);
          debugPrint('Sync: Local history updated with cloud data.');
        } else {
          debugPrint('Sync: Local history already up to date.');
        }
      }
      return true;
    } catch (e) {
      debugPrint('Sync: Error syncing from cloud: $e');
      return false;
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<String> _mergeHistory(List<String> local, List<String> cloud, DateTime cloudUpdatedAt) {
    final Map<String, Map<String, dynamic>> map = {};
    
    // 1. Process cloud items
    final Set<String> cloudIds = {};
    for (final itemStr in cloud) {
      try {
        final item = json.decode(itemStr);
        final obj = WatchHistoryItem.fromJson(item);
        final id = obj.uniqueId;
        cloudIds.add(id);
        map[id] = item;
      } catch (_) {}
    }
    
    // 2. Process local items
    for (final itemStr in local) {
      try {
        final item = json.decode(itemStr);
        final obj = WatchHistoryItem.fromJson(item);
        final id = obj.uniqueId;
        
        if (map.containsKey(id)) {
          // Conflict resolution: Newer timestamp wins
          final cloudItem = map[id]!;
          final localTime = obj.timestamp.toUtc();
          final cloudTime = DateTime.parse(cloudItem['timestamp']).toUtc();
          
          if (localTime.isAfter(cloudTime)) {
            map[id] = item;
          }
        } else {
          // Item exists locally but NOT in cloud.
          // Is it a NEW local item or was it DELETED in the cloud?
          final localTime = obj.timestamp.toUtc();
          if (localTime.isAfter(cloudUpdatedAt)) {
            debugPrint('Sync: Keeping new local item: ${obj.title} ($localTime > $cloudUpdatedAt)');
            map[id] = item;
          } else {
            debugPrint('Sync: Dropping deleted item: ${obj.title} ($localTime <= $cloudUpdatedAt)');
          }
        }
      } catch (_) {}
    }
    
    final sorted = map.values.toList()
      ..sort((a, b) => DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp'])));
      
    // keep only last 20
    final limited = sorted.take(20).toList();
    return limited.map((e) => json.encode(e)).toList();
  }
}

