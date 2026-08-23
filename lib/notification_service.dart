import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:lumino_app_moviestreaming/watch_history_service.dart';
import 'package:lumino_app_moviestreaming/primebox_service.dart';

class NotificationService {
  static const String _appUserIdKey = 'app_user_id';
  static const String _watchedSeriesKey = 'notification_watched_series';
  static const String _lastCheckedAtKey = 'notification_last_checked_at';

  /// In-memory cache so repeated calls (e.g. every 10 s from history timer)
  /// don't re-read hardware / Keychain on every tick.
  static String? _cachedAppUserId;

  /// Tracks the last time each series title was synced to Supabase.
  /// Prevents flooding Supabase with upserts when the history timer fires every 10 s.
  static final Map<String, DateTime> _lastSyncTime = {};
  static const Duration _syncDebounce = Duration(seconds: 60);

  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static RealtimeChannel? _realtimeChannel;

  /// Initializes local notification packages for Windows, Android, and iOS.
  static Future<void> init() async {
    try {
      debugPrint('NotificationService: Initializing notifications...');
      
      // 1. Get or generate the unique local device identifier
      final appUserId = await getAppUserId();
      debugPrint('NotificationService: App User ID: $appUserId');

      // 1.5. Migrate pre-existing watch history items so they get immediate notifications
      await _migratePreExistingWatchHistory();

      // 2. Initialize Platform-Specific Notifications
      if (!kIsWeb && Platform.isWindows) {
        // Setup local_notifier for Windows Toast notifications
        await localNotifier.setup(
          appName: 'Lumino',
        );
        debugPrint('NotificationService: Windows Local Notifier initialized.');
      } else if (Platform.isAndroid || Platform.isIOS) {
        // Setup flutter_local_notifications for Android/iOS
        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/ic_launcher');

        const DarwinInitializationSettings initializationSettingsDarwin =
            DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

        const InitializationSettings initializationSettings = InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

        await _flutterLocalNotificationsPlugin.initialize(
          settings: initializationSettings,
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            debugPrint('NotificationService: Notification clicked with payload: ${response.payload}');
          },
        );
        
        // Request permissions for Android 13+ / iOS
        if (Platform.isAndroid) {
          final androidPlugin = _flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>();
          await androidPlugin?.requestNotificationsPermission();

          // Create standard high importance notification channel
          await androidPlugin?.createNotificationChannel(
            const AndroidNotificationChannel(
              'lumino_push_notifications',
              'Lumino Notifications',
              description: 'Notifications for episodes and premium additions',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
          debugPrint('NotificationService: Android high importance notification channel created.');
        }
        
        debugPrint('NotificationService: Mobile Local Notifications initialized.');
      }

      // 3. Sync profile to database (helps register device & restore cross-device watched series)
      await syncProfileToCloud();
      await syncCrossDeviceWatchedSeries();

      // 4. Start listening to Postgres changes in real time
      listenToRealtimeReleases();

      // 5. Catch up on missed releases since the last launch
      await checkForNewReleases();

      // 6. Local periodic checks are offloaded entirely to the Supabase Cloud Scraper Cron!
      // start30MinPrimeboxCacheCheck();
      // start3HrSeriesDetailCheck();

      // 7. Initialize Firebase FCM and sync push token
      await _initFcm();
    } catch (e) {
      debugPrint('NotificationService: Initialization error: $e');
    }
  }

  static Future<void> _migratePreExistingWatchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = await WatchHistoryService.getHistory();
      
      if (history.isNotEmpty) {
        final List<String> watched = prefs.getStringList(_watchedSeriesKey) ?? [];
        bool changed = false;
        
        for (var item in history) {
          if (item.mediaType == 'tv') {
            final cleanTitle = _cleanTitle(item.title);
            
            if (cleanTitle.isNotEmpty && !watched.contains(cleanTitle)) {
              watched.add(cleanTitle);
              changed = true;
              final refinedDisplay = _getRefinedDisplayName(item.title);
              debugPrint('NotificationService: Auto-migrated pre-existing watched series "$refinedDisplay" (Key: "$cleanTitle")');
            }
          }
        }
        
        if (changed) {
          await prefs.setStringList(_watchedSeriesKey, watched);
          await syncProfileToCloud(watchedList: watched);
        }
      }
    } catch (e) {
      debugPrint('NotificationService: Error migrating pre-existing watch history: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PERMANENT DEVICE ID — survives uninstall / logout / data clear
  // ─────────────────────────────────────────────────────────────────────────

  /// Secure storage key for iOS/macOS Keychain (persists across app reinstalls).
  static const String _keychainKey = 'lumino_app_user_id';

  /// Returns a stable, permanent device-bound UUID.
  ///
  /// Strategy per platform:
  ///  • Android  → deterministic UUID v5 seeded from ANDROID_ID
  ///               (ANDROID_ID is stable per device + user account)
  ///  • iOS/macOS → UUID stored in Keychain via flutter_secure_storage
  ///               (Keychain survives app uninstall on iOS)
  ///  • Windows  → deterministic UUID v5 seeded from MachineGuid registry key
  ///  • Other    → random UUID cached in SharedPreferences (best-effort)
  ///
  /// SharedPreferences is used as a fast in-memory cache, but is NEVER the
  /// sole source of truth — the hardware/keychain value always wins.
  static Future<String> getAppUserId() async {
    // Return cached value immediately to avoid repeated hardware reads
    if (_cachedAppUserId != null) return _cachedAppUserId!;
    try {
      // ── Android ──────────────────────────────────────────────────────────
      if (!kIsWeb && Platform.isAndroid) {
        _cachedAppUserId = await _getAndroidDeviceId();
        return _cachedAppUserId!;
      }

      // ── iOS / macOS — Keychain (survives uninstall) ───────────────────────
      if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        _cachedAppUserId = await _getIosDeviceId();
        return _cachedAppUserId!;
      }

      // ── Windows — MachineGuid registry key ───────────────────────────────
      if (!kIsWeb && Platform.isWindows) {
        _cachedAppUserId = await _getWindowsDeviceId();
        return _cachedAppUserId!;
      }
    } catch (e) {
      debugPrint('NotificationService: getAppUserId hardware lookup failed, using fallback: $e');
    }

    // ── Generic fallback (Linux / Web / error) ────────────────────────────
    _cachedAppUserId = await _getFallbackDeviceId();
    return _cachedAppUserId!;
  }

  /// Android: ANDROID_ID → deterministic UUID v5.
  static Future<String> _getAndroidDeviceId() async {
    final info = await DeviceInfoPlugin().androidInfo;
    final androidId = info.id; // ANDROID_ID — stable per device+user
    if (androidId.isNotEmpty) {
      final id = _uuidV5(androidId);
      debugPrint('NotificationService: Android device ID derived from ANDROID_ID.');
      // Cache it so other code paths reading SharedPreferences still see it
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_appUserIdKey, id);
      return id;
    }
    return await _getFallbackDeviceId();
  }

  /// iOS/macOS: Keychain-persisted UUID (survives app uninstall on iOS).
  static Future<String> _getIosDeviceId() async {
    const storage = FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    String? id = await storage.read(key: _keychainKey);
    if (id != null && id.isNotEmpty) {
      debugPrint('NotificationService: iOS/macOS device ID restored from Keychain.');
      // Refresh SharedPreferences cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_appUserIdKey, id);
      return id;
    }
    // Not in Keychain — generate and store permanently
    id = _generateRandomUuid();
    await storage.write(key: _keychainKey, value: id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appUserIdKey, id);
    debugPrint('NotificationService: iOS/macOS device ID generated and saved to Keychain.');
    return id;
  }

  /// Windows: HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid → deterministic UUID v5.
  static Future<String> _getWindowsDeviceId() async {
    try {
      final result = await Process.run(
        'reg',
        ['query', r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid'],
        runInShell: true,
      );
      final output = result.stdout.toString();
      final match = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch(output);
      if (match != null) {
        final machineGuid = match.group(1)!.trim();
        final id = _uuidV5(machineGuid);
        debugPrint('NotificationService: Windows device ID derived from MachineGuid.');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_appUserIdKey, id);
        return id;
      }
    } catch (e) {
      debugPrint('NotificationService: Windows MachineGuid read failed: $e');
    }
    return await _getFallbackDeviceId();
  }

  /// Generic fallback: read SharedPreferences cache, or generate a random UUID.
  /// NOTE: This does NOT survive uninstall — only used when hardware ID is unavailable.
  static Future<String> _getFallbackDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_appUserIdKey);
    if (id != null && id.isNotEmpty) return id;
    id = _generateRandomUuid();
    await prefs.setString(_appUserIdKey, id);
    debugPrint('NotificationService: Fallback device ID generated (not hardware-bound).');
    return id;
  }

  /// Generates a deterministic UUID v5 (SHA-1 name-based) from [name].
  /// Two devices with the same hardware ID will always get the same UUID.
  static String _uuidV5(String name) {
    // DNS namespace UUID as the seed namespace (RFC 4122)
    const namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';
    final nsBytes = _hexToBytes(namespace.replaceAll('-', ''));
    final nameBytes = utf8.encode(name);
    final data = Uint8List(nsBytes.length + nameBytes.length)
      ..setAll(0, nsBytes)
      ..setAll(nsBytes.length, nameBytes);

    final hash = crypto.sha1.convert(data).bytes;
    final b = Uint8List.fromList(hash);

    // Set version 5 bits
    b[6] = (b[6] & 0x0f) | 0x50;
    // Set variant bits
    b[8] = (b[8] & 0x3f) | 0x80;

    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
        '${hex(b[4])}${hex(b[5])}-'
        '${hex(b[6])}${hex(b[7])}-'
        '${hex(b[8])}${hex(b[9])}-'
        '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Generates a random RFC4122 v4 UUID (used when hardware ID is unavailable).
  static String _generateRandomUuid() {
    final random = math.Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    // Set version to 4
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122
    values[8] = (values[8] & 0x3f) | 0x80;
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) buffer.write('-');
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Registers interest in a series and syncs the full watched list to Supabase.
  ///
  /// • NEW series   → always syncs to Supabase immediately.
  /// • KNOWN series → syncs to Supabase at most once per [_syncDebounce] (60 s).
  ///
  /// This ensures Supabase is always up-to-date without flooding it with upserts
  /// from the 10-second history timer in the video player.
  static Future<void> registerSeriesWatch(String seriesTitle) async {
    if (seriesTitle.isEmpty) return;
    final cleanTitle = _cleanTitle(seriesTitle);
    if (cleanTitle.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> watched = prefs.getStringList(_watchedSeriesKey) ?? [];

      bool isNew = false;
      if (!watched.contains(cleanTitle)) {
        watched.add(cleanTitle);
        await prefs.setStringList(_watchedSeriesKey, watched);
        isNew = true;

        final refinedDisplay = _getRefinedDisplayName(seriesTitle);
        debugPrint('NotificationService: New series registered "$refinedDisplay" (key: "$cleanTitle")');
      }

      // Always check/capture the series detail baseline asynchronously.
      // _captureInitialSeriesDetail has a built-in check to prevent duplicate work
      // if the series already exists in Supabase. This heals records that were
      // previously saved locally but missed by Supabase due to earlier bugs.
      _captureInitialSeriesDetail(cleanTitle);

      // Decide whether to sync to Supabase now:
      //  • Always sync for new series (isNew == true)
      //  • For known series, throttle to once per _syncDebounce to avoid spam
      final now = DateTime.now();
      final lastSync = _lastSyncTime[cleanTitle];
      final shouldSync = isNew || lastSync == null || now.difference(lastSync) >= _syncDebounce;

      if (shouldSync) {
        _lastSyncTime[cleanTitle] = now;
        await syncProfileToCloud(watchedList: watched);
        debugPrint('NotificationService: Synced "$cleanTitle" to Supabase (isNew: $isNew).');
      }
    } catch (e) {
      debugPrint('NotificationService: Error registering series watch: $e');
    }
  }

  /// Syncs this device's watched series and optional authenticated user link to Supabase.
  ///
  /// Uses `onConflict: 'app_user_id'` so the upsert correctly UPDATES the
  /// existing row rather than inserting a duplicate.
  static Future<void> syncProfileToCloud({List<String>? watchedList}) async {
    try {
      final appUserId = await getAppUserId();
      final supabaseUser = Supabase.instance.client.auth.currentUser;

      final prefs = await SharedPreferences.getInstance();
      final watched = watchedList ?? prefs.getStringList(_watchedSeriesKey) ?? [];

      debugPrint(
        'NotificationService: Syncing profile → appUserId=$appUserId '
        'supabaseUser=${supabaseUser?.id ?? "(guest)"} '
        'watchedCount=${watched.length} series=$watched',
      );

      await Supabase.instance.client
          .from('user_notification_profiles')
          .upsert(
            {
              'app_user_id': appUserId,
              'supabase_user_id': supabaseUser?.id,
              'watched_series': watched,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'app_user_id', // ← tells Supabase to UPDATE on duplicate app_user_id
          );

      debugPrint('NotificationService: ✅ Profile synced to Supabase successfully.');
    } catch (e, st) {
      // Log the full error so we can diagnose RLS / schema issues.
      debugPrint('NotificationService: ❌ syncProfileToCloud FAILED: $e\n$st');
    }
  }

  /// Syncs dynamic series subscriptions across all devices the user is logged into.
  static Future<void> syncCrossDeviceWatchedSeries() async {
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    if (supabaseUser == null) return;
    
    try {
      final appUserId = await getAppUserId();
      debugPrint('NotificationService: Performing cross-device sync for user ${supabaseUser.id}...');
      
      // Fetch all devices' profiles linked to this authenticated user ID
      final response = await Supabase.instance.client
          .from('user_notification_profiles')
          .select('watched_series')
          .eq('supabase_user_id', supabaseUser.id);
      
      if (response.isNotEmpty) {
        // Add current local items
        final prefs = await SharedPreferences.getInstance();
        final localList = prefs.getStringList(_watchedSeriesKey) ?? [];
        
        
        // Add from all other devices of the same user â€” de-duplicate by cleaned key
        final Map<String, String> deduped = {}; // cleanedKey â†’ originalTitle
        for (final item in localList) {
          final k = _cleanTitle(item);
          if (k.isNotEmpty) deduped[k] = item;
        }
        for (var profile in response) {
          var watchedVal = profile['watched_series'];
          if (watchedVal is String && watchedVal.isNotEmpty) {
            try {
              final decoded = json.decode(watchedVal);
              if (decoded is List) {
                watchedVal = decoded;
              }
            } catch (_) {}
          }
          if (watchedVal is List) {
            for (final raw in watchedVal) {
              final str = raw.toString();
              final k = _cleanTitle(str);
              if (k.isNotEmpty && !deduped.containsKey(k)) {
                deduped[k] = str;
              }
            }
          }
        }
        
        final mergedList = deduped.values.toList();
        await prefs.setStringList(_watchedSeriesKey, mergedList);
        
        // Update Supabase with the consolidated list
        await Supabase.instance.client.from('user_notification_profiles').upsert({
          'app_user_id': appUserId,
          'supabase_user_id': supabaseUser.id,
          'watched_series': mergedList,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        
        debugPrint('NotificationService: Cross-device sync completed! Total subscribed series: ${mergedList.length}');
      }
    } catch (e) {
      debugPrint('NotificationService: Cross-device sync failed (Table may need setup): $e');
    }
  }

  /// Listens to Supabase Postgres Realtime changes on `new_content_releases` table.
  static void listenToRealtimeReleases() {
    try {
      if (_realtimeChannel != null) {
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      }
      
      debugPrint('NotificationService: Setting up Realtime subscriber for "new_content_releases"...');
      
      _realtimeChannel = Supabase.instance.client.channel('public:new_content_releases');
      
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'new_content_releases',
        callback: (payload) async {
          debugPrint('NotificationService: Real-time content release insert received: ${payload.newRecord}');
          await _processContentRelease(payload.newRecord);
        },
      ).subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('NotificationService: Successfully subscribed to Realtime Postgres insertions.');
        } else {
          debugPrint('NotificationService: Realtime state: $status. Error: $error');
        }
      });
    } catch (e) {
      debugPrint('NotificationService: Realtime setup failed: $e');
    }
  }

  static Future<void> _processContentRelease(Map<String, dynamic> record) async {
    try {
      final id = record['id'] as int? ?? DateTime.now().millisecondsSinceEpoch % 100000;

      // Prevent duplicate notifications for already processed/delivered releases
      if (await isReleaseProcessed(id)) {
        debugPrint('NotificationService: Skipping duplicate local notification for release ID $id ("${record['title'] ?? ''}")');
        return;
      }

      final title = record['title'] as String? ?? '';
      final mediaType = record['media_type'] as String? ?? '';
      final season = record['season'] as int?;
      final episode = record['episode'] as int?;
      final episodeTitle = record['episode_title'] as String?;
      final category = record['category'] as String?;
      
      if (title.isEmpty) return;
      
      // 1. Check for Universal Notification
      if (category == 'trending' || category == 'cinema' || category == 'top_series') {
        String categoryLabel = 'Trending Now';
        if (category == 'cinema') categoryLabel = 'Cinema Releases';
        if (category == 'top_series') categoryLabel = 'Top Series This Week';
        
        final refinedTitle = _getRefinedDisplayName(title);
        
        await markReleaseAsProcessed(id);
        await showLocalNotification(
          id: id,
          title: 'ðŸ”¥ New in $categoryLabel',
          body: 'Check out "$refinedTitle", which is now available under $categoryLabel!',
          payload: 'universal:$mediaType:$title',
        );
        return;
      }
      
      // 2. Check for Dynamic Episode Notification
      if (mediaType == 'tv' || category == 'episode' || (season != null && episode != null)) {
        final prefs = await SharedPreferences.getInstance();
        final watched = prefs.getStringList(_watchedSeriesKey) ?? [];
        
        // Fuzzy match: clean the release title, then check if any watched key
        // is contained within it OR if it starts with a watched key.
        // e.g. watched has "the boys" and release is "The Boys" â†’ match.
        final cleanReleaseTitle = _cleanTitle(title);
        
        String? matchedWatchedKey;
        for (final key in watched) {
          final cleanKey = _cleanTitle(key); // ensure stored keys are also normalized
          if (cleanKey.isEmpty) continue;
          // Primary: exact match after cleaning
          if (cleanReleaseTitle == cleanKey) {
            matchedWatchedKey = key;
            break;
          }
          // Secondary: release title starts with the watched key (e.g. "the boys s6" starts with "the boys")
          if (cleanReleaseTitle.startsWith(cleanKey)) {
            matchedWatchedKey = key;
            break;
          }
          // Tertiary: watched key starts with release title (e.g. watched "the boys s1-s5" vs release "the boys")
          if (cleanKey.startsWith(cleanReleaseTitle) && cleanReleaseTitle.length > 3) {
            matchedWatchedKey = key;
            break;
          }
        }
        
        if (matchedWatchedKey != null) {
          final sNum = season ?? 1;
          final epNum = episode ?? 1;
          final epTitleSuffix = (episodeTitle != null && episodeTitle.isNotEmpty)
              ? ': "$episodeTitle"'
              : '';
          
          final refinedTitle = _getRefinedDisplayName(title);
          
          debugPrint('NotificationService: MATCH! Release "$title" matched watched key "$matchedWatchedKey". Sending notification.');
          
          await markReleaseAsProcessed(id);
          await showLocalNotification(
            id: id,
            title: 'ðŸŽ¬ New Episode of $refinedTitle!',
            body: 'Season $sNum, Episode $epNum$epTitleSuffix is now streaming!',
            payload: 'episode:tv:$title:$sNum:$epNum',
          );
        } else {
          debugPrint('NotificationService: No match for release "$title" (cleaned: "$cleanReleaseTitle") in watched list: $watched');
        }
      }
    } catch (e) {
      debugPrint('NotificationService: Error processing release record: $e');
    }
  }

  /// Checks for any content releases added to Supabase while the app was closed.
  static Future<void> checkForNewReleases() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckedStr = prefs.getString(_lastCheckedAtKey);
      
      final now = DateTime.now().toUtc();
      DateTime lastChecked = now.subtract(const Duration(hours: 4)); // Default lookback
      
      if (lastCheckedStr != null) {
        lastChecked = DateTime.parse(lastCheckedStr).toUtc();
      }
      
      debugPrint('NotificationService: Catching up on missed releases since $lastChecked...');
      
      final response = await Supabase.instance.client
          .from('new_content_releases')
          .select()
          .gt('created_at', lastChecked.toIso8601String())
          .order('created_at', ascending: true);
      
      if (response.isNotEmpty) {
        debugPrint('NotificationService: Found ${response.length} missed releases. Evaluating...');
        
        final List<Map<String, dynamic>> cinemaItems = [];
        final List<Map<String, dynamic>> topSeriesItems = [];
        final List<Map<String, dynamic>> trendingItems = [];
        final List<Map<String, dynamic>> otherItems = [];

        for (var record in response) {
          final category = record['category'] as String?;
          if (category == 'cinema') {
            cinemaItems.add(record);
          } else if (category == 'top_series') {
            topSeriesItems.add(record);
          } else if (category == 'trending') {
            trendingItems.add(record);
          } else {
            otherItems.add(record);
          }
        }

        // Keep only the LATEST 2 from each category (since they are ordered ascending, latest are at the end)
        final List<Map<String, dynamic>> filteredList = [];
        
        if (cinemaItems.length > 2) {
          filteredList.addAll(cinemaItems.sublist(cinemaItems.length - 2));
        } else {
          filteredList.addAll(cinemaItems);
        }

        if (topSeriesItems.length > 2) {
          filteredList.addAll(topSeriesItems.sublist(topSeriesItems.length - 2));
        } else {
          filteredList.addAll(topSeriesItems);
        }

        if (trendingItems.length > 2) {
          filteredList.addAll(trendingItems.sublist(trendingItems.length - 2));
        } else {
          filteredList.addAll(trendingItems);
        }

        // Add all other notifications (like personalized watched episodes)
        filteredList.addAll(otherItems);

        // Re-sort chronologically
        filteredList.sort((a, b) {
          final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.now();
          final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.now();
          return aTime.compareTo(bTime);
        });

        debugPrint('NotificationService: Capped startup notifications to ${filteredList.length} items.');
        for (var record in filteredList) {
          await _processContentRelease(record);
        }
      } else {
        debugPrint('NotificationService: No missed releases.');
      }
      
      // Update check time
      await prefs.setString(_lastCheckedAtKey, now.toIso8601String());
      
      // Sync last check time to the database profile
      final appUserId = await getAppUserId();
      await Supabase.instance.client.from('user_notification_profiles').upsert({
        'app_user_id': appUserId,
        'last_checked_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('NotificationService: Failed to check for missed releases: $e');
    }
  }

  /// Publishes a new content release row to Supabase `new_content_releases`.
  /// Call this whenever a new episode or movie is added to the app.
  /// [title]       - Series/movie title (e.g. 'The Boys')
  /// [mediaType]   - 'tv' or 'movie'
  /// [season]      - Season number (nullable for movies)
  /// [episode]     - Episode number (nullable for movies)
  /// [episodeTitle]- Optional episode name
  /// [category]    - Optional: 'episode', 'trending', 'cinema', 'top_series'
  static Future<bool> publishNewRelease({
    required String title,
    required String mediaType,
    int? season,
    int? episode,
    String? episodeTitle,
    String category = 'episode',
  }) async {
    try {
      // 1. Concurrency Check: Verify if the exact same release already exists to prevent duplication
      var checkQuery = Supabase.instance.client
          .from('new_content_releases')
          .select('id')
          .eq('title', title)
          .eq('media_type', mediaType)
          .eq('category', category);

      if (season != null) {
        checkQuery = checkQuery.eq('season', season);
      } else {
        checkQuery = checkQuery.filter('season', 'is', null);
      }

      if (episode != null) {
        checkQuery = checkQuery.eq('episode', episode);
      } else {
        checkQuery = checkQuery.filter('episode', 'is', null);
      }

      final existing = await checkQuery.maybeSingle();
      if (existing != null) {
        debugPrint('NotificationService: Release for "$title" ($category, S${season}E$episode) already exists. Skipping duplicate insert.');
        return true;
      }

      // 2. Safe Insert
      await Supabase.instance.client.from('new_content_releases').insert({
        'title': title,
        'media_type': mediaType,
        'season': season,
        'episode': episode,
        'episode_title': episodeTitle,
        'category': category,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint('NotificationService: Successfully published new release for "$title".');
      return true;
    } catch (e) {
      // Catch duplicate key / unique constraint exceptions in case database index is triggered concurrently
      final errStr = e.toString();
      if (errStr.contains('duplicate key') || errStr.contains('23505')) {
        debugPrint('NotificationService: Ignored concurrent duplicate insertion of "$title".');
        return true;
      }
      debugPrint('NotificationService: Failed to publish release: $e');
      return false;
    }
  }

  /// Displays the native local notification on either desktop or mobile.
  static Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      if (!kIsWeb && Platform.isWindows) {
        final notification = LocalNotification(
          identifier: id.toString(),
          title: title,
          body: body,
        );
        
        notification.onShow = () {
          debugPrint('NotificationService: Windows Toast displayed.');
        };
        
        await notification.show();
      } else if (Platform.isAndroid || Platform.isIOS) {
        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'lumino_push_notifications',
          'Lumino Notifications',
          channelDescription: 'Notifications for episodes and premium additions',
          importance: Importance.max,
          priority: Priority.high,
        );
        
        const NotificationDetails platformDetails = NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );
        
        await _flutterLocalNotificationsPlugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: platformDetails,
          payload: payload,
        );
      }
    } catch (e) {
      debugPrint('NotificationService: Error displaying notification: $e');
    }
  }

  /// Cleans and normalizes series titles for robust, case-insensitive matching.
  static String _cleanTitle(String t) {
    // 1. Remove bracketed text like [Hindi], [Dual Audio], [720p], [From S1-S4]
    t = t.replaceAll(RegExp(r'\[.*?\]'), '');
    // 2. Remove parenthesized text like (Hindi), (From S1-S4)
    t = t.replaceAll(RegExp(r'\(.*?\)'), '');
    // 3. Remove "From S1-S4", "From S01-S05", "From S1 to S5"
    t = t.replaceAll(RegExp(r'From\s+S\d+\s*-\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'From\s+S\d+\s*to\s*S\d+', caseSensitive: false), '');
    // 4. Remove Season ranges like S1-S5, S01-S05, S1 to S5
    t = t.replaceAll(RegExp(r'S\d+\s*-\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+\s*to\s*S\d+', caseSensitive: false), '');
    // 5. Remove single Season/Episode markers
    t = t.replaceAll(RegExp(r'Season\s+\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Episode\s+\d+', caseSensitive: false), '');
    // 6. Remove "Hindi Dubbed", "Eng Sub" etc.
    t = t.replaceAll(RegExp(r'Hindi\s+Dub\w*', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Eng\w*\s+Sub\w*', caseSensitive: false), '');
    // 7. Remove special characters but keep spaces/letters/numbers
    t = t.replaceAll(RegExp(r'[^\w\s]'), '');
    // 8. Normalize spaces and convert to lowercase for case-insensitive matching
    return t.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Refines display names for dynamic & universal notifications, keeping correct casing.
  static String _getRefinedDisplayName(String t) {
    // 1. Remove bracketed text like [Hindi], [From S1-S4]
    t = t.replaceAll(RegExp(r'\[.*?\]'), '');
    // 2. Remove parenthesized text like (Hindi), (From S1-S4)
    t = t.replaceAll(RegExp(r'\(.*?\)'), '');
    // 3. Remove "From S1-S4", "From S01-S05", "From S1 to S5"
    t = t.replaceAll(RegExp(r'From\s+S\d+\s*-\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'From\s+S\d+\s*to\s*S\d+', caseSensitive: false), '');
    // 4. Remove Season ranges like S1-S5, S01-S05, S1 to S5
    t = t.replaceAll(RegExp(r'S\d+\s*-\s*S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+\s*to\s*S\d+', caseSensitive: false), '');
    // 5. Remove single Season/Episode markers
    t = t.replaceAll(RegExp(r'Season\s+\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'S\d+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'Episode\s+\d+', caseSensitive: false), '');
    // 6. Clean up trailing colons/dashes/spaces
    t = t.replaceAll(RegExp(r'\s*[:-]\s*$'), '');
    return t.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  // ==========================================
  // BACKGROUND CHECKERS & REALTIME COMPARISONS
  // ==========================================

  /// Sets up and starts the periodic 30-minute global check for new home, cinema, and top series content.
  static Future<void> start30MinPrimeboxCacheCheck() async {
    // Run immediately on launch
    _runPrimeboxCacheCheck();
    // Schedule periodic timer
    Timer.periodic(const Duration(minutes: 30), (timer) {
      _runPrimeboxCacheCheck();
    });
  }

  static Future<void> _runPrimeboxCacheCheck() async {
    debugPrint('NotificationService: Running 30-minute Primebox Cache Check...');
    try {
      final List<Map<String, dynamic>> itemsToCheck = [];

      // 1. Fetch Home API
      try {
        final res = await http.get(Uri.parse('https://hqkkwzafev6lvngmejpksui3mi0bbnoj.lambda-url.ap-south-1.on.aws/home'), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        }).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final data = json.decode(res.body)['data'];
          final ops = data['operatingList'] as List?;
          if (ops != null) {
            for (final op in ops) {
              final type = op['type'];
              final opTitle = op['title']?.toString() ?? '';
              
              // Categorize sections inside Home API
              String category = 'trending';
              if (opTitle.toLowerCase().contains('top series') || opTitle.toLowerCase().contains('series')) {
                category = 'top_series';
              } else if (opTitle.toLowerCase().contains('cinema') || opTitle.toLowerCase().contains('movies')) {
                category = 'cinema';
              }

              if (type == 'BANNER') {
                final bannerItems = (op['banner']?['items'] as List?) ?? [];
                for (final item in bannerItems) {
                  final title = item['title']?.toString() ?? '';
                  final detailPath = item['detailPath']?.toString() ?? '';
                  final subjectType = item['subjectType'] ?? 1;
                  if (title.isNotEmpty && detailPath.isNotEmpty) {
                    itemsToCheck.add({
                      'title': title,
                      'detailPath': detailPath,
                      'mediaType': subjectType == 1 ? 'movie' : 'tv',
                      'category': subjectType == 2 ? 'top_series' : category,
                    });
                  }
                }
              } else if (op['subjects'] != null) {
                final subjects = op['subjects'] as List;
                for (final item in subjects) {
                  final title = item['title']?.toString() ?? '';
                  final detailPath = item['detailPath']?.toString() ?? '';
                  final subjectType = item['subjectType'] ?? 1;
                  if (title.isNotEmpty && detailPath.isNotEmpty) {
                    itemsToCheck.add({
                      'title': title,
                      'detailPath': detailPath,
                      'mediaType': subjectType == 1 ? 'movie' : 'tv',
                      'category': subjectType == 2 ? 'top_series' : category,
                    });
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('NotificationService: Home cache check API fetch error: $e');
      }

      // 2. Fetch Movies API (Uses operatingList just like Home API)
      try {
        final res = await http.get(Uri.parse('https://hqkkwzafev6lvngmejpksui3mi0bbnoj.lambda-url.ap-south-1.on.aws/movie'), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        }).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final data = json.decode(res.body)['data'];
          final ops = data['operatingList'] as List?;
          if (ops != null) {
            for (final op in ops) {
              final type = op['type'];
              if (type == 'BANNER') {
                final bannerItems = (op['banner']?['items'] as List?) ?? [];
                for (final item in bannerItems) {
                  final title = item['title']?.toString() ?? '';
                  final detailPath = item['detailPath']?.toString() ?? '';
                  final subjectType = item['subjectType'] ?? 1;
                  if (title.isNotEmpty && detailPath.isNotEmpty) {
                    itemsToCheck.add({
                      'title': title,
                      'detailPath': detailPath,
                      'mediaType': subjectType == 1 ? 'movie' : 'tv',
                      'category': 'cinema',
                    });
                  }
                }
              } else if (op['subjects'] != null) {
                final subjects = op['subjects'] as List;
                for (final item in subjects) {
                  final title = item['title']?.toString() ?? '';
                  final detailPath = item['detailPath']?.toString() ?? '';
                  final subjectType = item['subjectType'] ?? 1;
                  if (title.isNotEmpty && detailPath.isNotEmpty) {
                    itemsToCheck.add({
                      'title': title,
                      'detailPath': detailPath,
                      'mediaType': subjectType == 1 ? 'movie' : 'tv',
                      'category': 'cinema',
                    });
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('NotificationService: Movies cache check API fetch error: $e');
      }

      // 3. Fetch Animation API (Uses items list)
      try {
        final res = await http.get(Uri.parse('https://hqkkwzafev6lvngmejpksui3mi0bbnoj.lambda-url.ap-south-1.on.aws/animation'), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        }).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final data = json.decode(res.body)['data'];
          final items = data['items'] as List?;
          if (items != null) {
            for (final item in items) {
              if (item['countryName'] != 'Japan') continue;
              final title = item['title']?.toString() ?? '';
              final detailPath = item['detailPath']?.toString() ?? '';
              final subjectType = item['subjectType'] ?? 1;
              if (title.isNotEmpty && detailPath.isNotEmpty) {
                itemsToCheck.add({
                  'title': title,
                  'detailPath': detailPath,
                  'mediaType': subjectType == 1 ? 'movie' : 'tv',
                  'category': subjectType == 2 ? 'top_series' : 'trending',
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint('NotificationService: Animation cache check API fetch error: $e');
      }

      // Process newly found items and compare with DB/cache
      if (itemsToCheck.isNotEmpty) {
        final supabaseUser = Supabase.instance.client.auth.currentUser;
        final appUserId = await getAppUserId();

        int trendingCount = 0;
        int cinemaCount = 0;
        int topSeriesCount = 0;

        for (final item in itemsToCheck) {
          final title = item['title'];
          final detailPath = item['detailPath'];
          final mediaType = item['mediaType'];
          final category = item['category'];

          try {
            // Check if this detailPath is already registered/seen in 'primebox_home_cache'
            final existing = await Supabase.instance.client
                .from('primebox_home_cache')
                .select('detail_path')
                .eq('detail_path', detailPath)
                .maybeSingle();

            if (existing == null) {
              debugPrint('NotificationService: New global item detected: "$title" (detailPath: $detailPath, category: $category)');
              
              // 1. Always insert into primebox_home_cache so we don't process it again
              await Supabase.instance.client.from('primebox_home_cache').insert({
                'title': title,
                'detail_path': detailPath,
                'category': category,
                'app_user_id': appUserId,
                'supabase_user_id': supabaseUser?.id,
                'created_at': DateTime.now().toUtc().toIso8601String(),
              });

              // 2. Publish to new_content_releases (capped at 2 notifications per section)
              bool shouldPublish = false;
              if (category == 'trending' && trendingCount < 2) {
                shouldPublish = true;
                trendingCount++;
              } else if (category == 'cinema' && cinemaCount < 2) {
                shouldPublish = true;
                cinemaCount++;
              } else if (category == 'top_series' && topSeriesCount < 2) {
                shouldPublish = true;
                topSeriesCount++;
              }

              if (shouldPublish) {
                await publishNewRelease(
                  title: title,
                  mediaType: mediaType,
                  category: category,
                );
              } else {
                debugPrint('NotificationService: Capping reached for category "$category". Registered in cache but not published to new_content_releases.');
              }
            }
          } catch (e) {
            debugPrint('NotificationService: Database error checking/inserting primebox cache: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('NotificationService: Error in 30-minute check: $e');
    }
  }

  /// Sets up and starts the periodic 3-hour check for watched series details updates.
  static Future<void> start3HrSeriesDetailCheck() async {
    // Run immediately on launch
    _runSeriesDetailCheck();
    // Schedule periodic timer
    Timer.periodic(const Duration(hours: 3), (timer) {
      _runSeriesDetailCheck();
    });
  }

  static Future<void> _runSeriesDetailCheck() async {
    debugPrint('NotificationService: Running 3-hour Watched Series Detail Check...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final watchedList = prefs.getStringList(_watchedSeriesKey) ?? [];
      if (watchedList.isEmpty) return;

      final appUserId = await getAppUserId();
      final supabaseUser = Supabase.instance.client.auth.currentUser;

      for (final rawTitle in watchedList) {
        final cleanTitle = _cleanTitle(rawTitle);
        if (cleanTitle.isEmpty) continue;

        try {
          // 1. Check if we have a stored baseline in user_watched_series_details in Supabase
          final existing = await Supabase.instance.client
              .from('user_watched_series_details')
              .select()
              .eq('app_user_id', appUserId)
              .eq('series_title', cleanTitle)
              .maybeSingle();

          String? detailPath;
          List<dynamic> oldSeasons = [];

          if (existing != null) {
            detailPath = existing['detail_path'];
            final rawSeasons = existing['seasons_data'];
            if (rawSeasons is List) {
              oldSeasons = rawSeasons;
            } else if (rawSeasons is String) {
              oldSeasons = json.decode(rawSeasons) as List;
            }
          }

          // If no detailPath was stored, let's search Primebox to resolve it
          if (detailPath == null || detailPath.isEmpty) {
            debugPrint('NotificationService: Resolving detailPath for series: "$cleanTitle"');
            final searchResults = await PrimeboxService.search(cleanTitle);
            
            // Search robustly for a series match
            PrimeboxItem? match;
            for (final item in searchResults) {
              if (item.subjectType == 2 && _cleanTitle(item.title) == cleanTitle) {
                match = item;
                break;
              }
            }
            if (match == null) {
              for (final item in searchResults) {
                if (item.subjectType == 2) {
                  match = item;
                  break;
                }
              }
            }

            if (match != null && match.detailPath.isNotEmpty) {
              detailPath = match.detailPath;
            } else {
              debugPrint('NotificationService: Could not resolve Primebox series for: "$cleanTitle"');
              continue; // Skip this show if we can't find it
            }
          }

          // 2. Fetch the latest detail data from Primebox Detail API
          final detailApi = 'https://hqkkwzafev6lvngmejpksui3mi0bbnoj.lambda-url.ap-south-1.on.aws/detail?detailPath=$detailPath';
          final res = await http.get(Uri.parse(detailApi), headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          }).timeout(const Duration(seconds: 15));

          if (res.statusCode != 200) continue;

          final body = json.decode(res.body);
          final data = body['data'];
          if (data == null) continue;

          final resource = data['resource'] ?? {};
          final pbSeasons = resource['seasons'] as List? ?? [];
          if (pbSeasons.isEmpty) continue;

          // Parse new seasons list: [{"se": seasonNum, "maxEp": maxEp}]
          final List<Map<String, dynamic>> newSeasons = pbSeasons.map((s) {
            return {
              'se': s['se'] as int? ?? 1,
              'maxEp': s['maxEp'] as int? ?? 0,
            };
          }).toList();

          // 3. Compare new seasons with old seasons
          if (existing == null) {
            // First time seeing this show for the user. Save the baseline!
            debugPrint('NotificationService: Storing baseline details for watched series "$cleanTitle"');
            await Supabase.instance.client.from('user_watched_series_details').insert({
              'app_user_id': appUserId,
              'supabase_user_id': supabaseUser?.id,
              'series_title': cleanTitle,
              'detail_path': detailPath,
              'seasons_data': newSeasons,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
          } else {
            // Compare latest season's episode count
            newSeasons.sort((a, b) => (a['se'] as int).compareTo(b['se'] as int));
            
            // Clean/map old seasons to compare properly
            final List<Map<String, dynamic>> parsedOldSeasons = oldSeasons.map((s) {
              final map = s as Map;
              return {
                'se': map['se'] as int? ?? 1,
                'maxEp': map['maxEp'] as int? ?? 0,
              };
            }).toList();
            
            parsedOldSeasons.sort((a, b) => (a['se'] as int).compareTo(b['se'] as int));

            if (newSeasons.isNotEmpty) {
              final newLatest = newSeasons.last;
              final newLatestSeasonNum = newLatest['se'] as int;
              final newLatestEpCount = newLatest['maxEp'] as int;

              // Find matching season in old data
              Map<String, dynamic>? oldMatch;
              for (final s in parsedOldSeasons) {
                if (s['se'] == newLatestSeasonNum) {
                  oldMatch = s;
                  break;
                }
              }

              bool episodeCountIncreased = false;
              int startEp = 1;

              if (oldMatch == null) {
                // Completely new season added!
                episodeCountIncreased = true;
                startEp = 1;
              } else {
                final oldEpCount = oldMatch['maxEp'] as int;
                if (newLatestEpCount > oldEpCount) {
                  episodeCountIncreased = true;
                  startEp = oldEpCount + 1;
                }
              }

              if (episodeCountIncreased) {
                debugPrint('NotificationService: WATCHED SERIES UPDATE! "$cleanTitle" season $newLatestSeasonNum episode count increased to $newLatestEpCount!');
                
                // Show notification immediately for the user
                final displayTitle = _getRefinedDisplayName(rawTitle);
                for (int ep = startEp; ep <= newLatestEpCount; ep++) {
                  await showLocalNotification(
                    id: DateTime.now().millisecondsSinceEpoch % 100000,
                    title: 'ðŸŽ¬ New Episode of $displayTitle!',
                    body: 'Season $newLatestSeasonNum, Episode $ep is now streaming!',
                    payload: 'episode:tv:$cleanTitle:$newLatestSeasonNum:$ep',
                  );

                  // Publish to Supabase so that other devices of the user sync this release
                  await publishNewRelease(
                    title: cleanTitle,
                    mediaType: 'tv',
                    season: newLatestSeasonNum,
                    episode: ep,
                    category: 'episode',
                  );
                }

                // Update stored details in Supabase
                await Supabase.instance.client.from('user_watched_series_details').update({
                  'seasons_data': newSeasons,
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                }).eq('app_user_id', appUserId).eq('series_title', cleanTitle);
              }
            }
          }
        } catch (e) {
          debugPrint('NotificationService: Error checking watched series detail: $e');
        }
      }
    } catch (e) {
      debugPrint('NotificationService: Watched series detail check outer error: $e');
    }
  }

  /// Resolves the series detail baseline in real-time when a user registers a watched series.
  static Future<void> _captureInitialSeriesDetail(String cleanTitle) async {
    try {
      final appUserId = await getAppUserId();
      final supabaseUser = Supabase.instance.client.auth.currentUser;

      // 1. First, check if this series is already tracked in user_watched_series_details.
      // This prevents hammering the Primebox API if we already have the baseline.
      final existing = await Supabase.instance.client
          .from('user_watched_series_details')
          .select('series_title')
          .eq('app_user_id', appUserId)
          .eq('series_title', cleanTitle)
          .maybeSingle();

      if (existing != null) {
        debugPrint('NotificationService: Baseline for "$cleanTitle" already exists. Skipping Primebox lookup.');
        return;
      }

      debugPrint('NotificationService: Capturing initial baseline detail for missing series: "$cleanTitle"');
      
      final searchResults = await PrimeboxService.search(cleanTitle);
      PrimeboxItem? match;
      for (final item in searchResults) {
        if (item.subjectType == 2 && _cleanTitle(item.title) == cleanTitle) {
          match = item;
          break;
        }
      }
      if (match == null) {
        for (final item in searchResults) {
          if (item.subjectType == 2) {
            match = item;
            break;
          }
        }
      }

      if (match != null && match.detailPath.isNotEmpty) {
        final detailApi = 'https://hqkkwzafev6lvngmejpksui3mi0bbnoj.lambda-url.ap-south-1.on.aws/detail?detailPath=${match.detailPath}';
        final res = await http.get(Uri.parse(detailApi), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        }).timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final body = json.decode(res.body);
          final data = body['data'];
          if (data != null) {
            final resource = data['resource'] ?? {};
            final pbSeasons = resource['seasons'] as List? ?? [];
            if (pbSeasons.isNotEmpty) {
              final List<Map<String, dynamic>> seasons = pbSeasons.map((s) {
                return {
                  'se': s['se'] as int? ?? 1,
                  'maxEp': s['maxEp'] as int? ?? 0,
                };
              }).toList();

              await Supabase.instance.client.from('user_watched_series_details').upsert({
                'app_user_id': appUserId,
                'supabase_user_id': supabaseUser?.id,
                'series_title': cleanTitle,
                'detail_path': match.detailPath,
                'seasons_data': seasons,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              }, onConflict: 'app_user_id,series_title');
              debugPrint('NotificationService: Baseline saved for "$cleanTitle"');
              return; // SUCCESS - Exit early
            }
          }
        }
      }

      // FALLBACK: If Primebox search fails (e.g. 422 for short titles like "From")
      // or doesn't return season counts, we MUST STILL record the series in Supabase.
      await Supabase.instance.client.from('user_watched_series_details').upsert({
        'app_user_id': appUserId,
        'supabase_user_id': supabaseUser?.id,
        'series_title': cleanTitle,
        'detail_path': match?.detailPath ?? '',
        'seasons_data': [], // Empty array as fallback
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'app_user_id,series_title');
      debugPrint('NotificationService: Fallback baseline saved for "$cleanTitle" (No Primebox detail)');
    } catch (e) {
      debugPrint('NotificationService: Error capturing initial series detail: $e');
    }
  }

  /// Initializes Firebase messaging and captures the FCM token.
  static Future<void> _initFcm() async {
    if (kIsWeb) return;
    // Firebase messaging is natively supported on mobile. Windows is skipped for FCM token capture.
    if (Platform.isWindows) return;

    try {
      debugPrint('NotificationService: Initializing Firebase Cloud Messaging...');
      
      // Request permissions
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('NotificationService: User granted push notification permission.');
      } else {
        debugPrint('NotificationService: User declined push notification permission.');
      }

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Get FCM token
      final token = await messaging.getToken();
      if (token != null) {
        debugPrint('NotificationService: Retrieved FCM Token: $token');
        await _syncFcmToken(token);
      }

      // Listen to token refresh
      messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('NotificationService: FCM Token refreshed: $newToken');
        await _syncFcmToken(newToken);
      });

      // Handle foreground messages when app is active
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('NotificationService: Foreground FCM message received: ${message.notification?.title}');
        final releaseIdStr = message.data['release_id'];
        if (releaseIdStr != null) {
          final releaseId = int.tryParse(releaseIdStr);
          if (releaseId != null) {
            await markReleaseAsProcessed(releaseId);
          }
        }
      });

    } catch (e) {
      debugPrint('NotificationService: Failed to initialize Firebase FCM: $e');
    }
  }

  /// Syncs/Upserts the device FCM token to the user_fcm_tokens table in Supabase.
  static Future<void> _syncFcmToken(String token) async {
    try {
      final appUserId = await getAppUserId();
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      final platform = kIsWeb ? 'web' : Platform.operatingSystem;

      debugPrint('NotificationService: Syncing FCM token to Supabase (appUserId: $appUserId, user: ${supabaseUser?.id})...');
      await Supabase.instance.client.from('user_fcm_tokens').upsert({
        'app_user_id': appUserId,
        'supabase_user_id': supabaseUser?.id,
        'fcm_token': token,
        'device_platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fcm_token');
      
      debugPrint('NotificationService: FCM token successfully registered in Supabase.');
    } catch (e) {
      debugPrint('NotificationService: Failed to sync FCM token to Supabase: $e');
    }
  }

  /// Public wrapper to sync/update the device FCM token to Supabase.
  /// Call this when the user's authentication state changes (login/logout) or on startup.
  static Future<void> syncFcmTokenToCloud() async {
    if (kIsWeb) return;
    if (Platform.isWindows) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _syncFcmToken(token);
      } else {
        debugPrint('NotificationService: Cannot sync FCM token, token is null.');
      }
    } catch (e) {
      debugPrint('NotificationService: Error in syncFcmTokenToCloud: $e');
    }
  }

  /// Unlinks the FCM token from any authenticated Supabase user.
  /// This should be called while the user is still logged in (before signing out).
  static Future<void> unlinkFcmTokenFromUser() async {
    if (kIsWeb) return;
    if (Platform.isWindows) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        final appUserId = await getAppUserId();
        final platform = kIsWeb ? 'web' : Platform.operatingSystem;

        debugPrint('NotificationService: Unlinking FCM token from user in Supabase (appUserId: $appUserId)...');
        await Supabase.instance.client.from('user_fcm_tokens').upsert({
          'app_user_id': appUserId,
          'supabase_user_id': null,
          'fcm_token': token,
          'device_platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'fcm_token');
        debugPrint('NotificationService: FCM token successfully unlinked.');
      }
    } catch (e) {
      debugPrint('NotificationService: Failed to unlink FCM token: $e');
    }
  }

  static const String _processedReleaseIdsKey = 'notification_processed_release_ids';

  /// Records that a release ID has been notified/processed to prevent duplicate alerts.
  static Future<void> markReleaseAsProcessed(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_processedReleaseIdsKey) ?? [];
      final idStr = id.toString();
      if (!list.contains(idStr)) {
        list.add(idStr);
        // Keep only the last 100 release IDs to avoid infinite growth
        if (list.length > 100) {
          list.removeRange(0, list.length - 100);
        }
        await prefs.setStringList(_processedReleaseIdsKey, list);
        debugPrint('NotificationService: Marked release ID $id as processed.');
      }
    } catch (e) {
      debugPrint('NotificationService: Error marking release as processed: $e');
    }
  }

  /// Checks if a release ID has already been notified/processed.
  static Future<bool> isReleaseProcessed(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_processedReleaseIdsKey) ?? [];
      return list.contains(id.toString());
    } catch (e) {
      debugPrint('NotificationService: Error checking processed status: $e');
      return false;
    }
  }
}

/// Top-level background message handler for Firebase Cloud Messaging.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('NotificationService: Handling background FCM message: ${message.messageId}');
  
  final releaseIdStr = message.data['release_id'];
  if (releaseIdStr != null) {
    final releaseId = int.tryParse(releaseIdStr);
    if (releaseId != null) {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('notification_processed_release_ids') ?? [];
      final idStr = releaseId.toString();
      if (!list.contains(idStr)) {
        list.add(idStr);
        if (list.length > 100) {
          list.removeRange(0, list.length - 100);
        }
        await prefs.setStringList('notification_processed_release_ids', list);
        debugPrint('NotificationService: Marked background release ID $releaseId as processed in FCM.');
      }
    }
  }
}
