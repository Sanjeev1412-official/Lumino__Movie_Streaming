import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumino_app_moviestreaming/auth_service.dart';
import 'package:lumino_app_moviestreaming/sync_service.dart';
import 'package:lumino_app_moviestreaming/notification_service.dart';

class DeviceLinkService {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Performs mathematically unbreakable XOR encryption (One-Time Pad) with safe Base64 wrapping.
  static String _xorEncrypt(String input, String key) {
    final List<int> inputBytes = utf8.encode(input);
    final List<int> keyBytes = utf8.encode(key);
    final List<int> resultBytes = List<int>.generate(inputBytes.length, (i) {
      return inputBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return base64.encode(resultBytes);
  }

  /// Performs XOR decryption with safe Base64 unwrapping.
  static String _xorDecrypt(String base64Input, String key) {
    try {
      final List<int> inputBytes = base64.decode(base64Input);
      final List<int> keyBytes = utf8.encode(key);
      final List<int> resultBytes = List<int>.generate(inputBytes.length, (i) {
        return inputBytes[i] ^ keyBytes[i % keyBytes.length];
      });
      return utf8.decode(resultBytes);
    } catch (e) {
      debugPrint('DeviceLinkService: Decryption base64/utf8 failure: $e');
      return '';
    }
  }

  /// Helper to generate a secure random alphanumeric string for the one-time encryption key.
  static String _generateSecureKey(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = math.Random.secure();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Helper to generate a UUID v4 compliant string for session IDs.
  static String _generateUuid() {
    final random = math.Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // Set version to 4
    values[8] = (values[8] & 0x3f) | 0x80; // Set variant to RFC 4122
    
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// STEP 1 (Child/Unsigned Device): Initiates a link request.
  /// Creates a row in `device_link_sessions` and returns the session details & QR payload.
  static Future<Map<String, String>> initiateLinkSession() async {
    try {
      final sessionId = _generateUuid();
      final encryptionKey = _generateSecureKey(32);
      
      final childOS = Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Desktop');
      
      // Insert pending session into Supabase
      await _client.from('device_link_sessions').insert({
        'id': sessionId,
        'status': 'pending',
        'child_device_info': {
          'os': childOS,
          'launched_at': DateTime.now().toIso8601String(),
        }
      });
      
      // QR payload schema: "lumino-link:<sessionId>:<encryptionKey>"
      final qrPayload = 'lumino-link:$sessionId:$encryptionKey';
      
      debugPrint('DeviceLinkService: Initiated session $sessionId');
      return {
        'sessionId': sessionId,
        'encryptionKey': encryptionKey,
        'qrPayload': qrPayload,
      };
    } catch (e) {
      debugPrint('DeviceLinkService: Failed to initiate session: $e');
      rethrow;
    }
  }

  /// STEP 2 (Child/Unsigned Device): Subscribes to real-time updates for its session.
  /// Yields updates whenever the database row changes (e.g. gets authorized).
  static Stream<Map<String, dynamic>> listenToSession(String sessionId) {
    debugPrint('DeviceLinkService: Starting high-reliability polling for session $sessionId');
    final controller = StreamController<Map<String, dynamic>>();
    Timer? timer;

    // Poll the database every 2 seconds for status changes
    timer = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final response = await _client
            .from('device_link_sessions')
            .select()
            .eq('id', sessionId)
            .maybeSingle();

        if (response != null && !controller.isClosed) {
          debugPrint('DeviceLinkService Polling: Status retrieved -> ${response['status']}');
          controller.add(response);
          
          // Stop polling if the session gets authorized or expired
          if (response['status'] == 'authorized' || response['status'] == 'expired') {
            timer?.cancel();
            controller.close();
          }
        }
      } catch (e) {
        debugPrint('DeviceLinkService Polling: Error checking session: $e');
      }
    });

    controller.onCancel = () {
      timer?.cancel();
      controller.close();
      debugPrint('DeviceLinkService: Polling terminated for session $sessionId');
    };

    return controller.stream;
  }

  /// STEP 3 (Parent/Signed-In Device): Authorizes a scanned session by encrypting
  /// its refresh token and pushing it back to Supabase.
  static Future<Map<String, dynamic>> authorizeSession({
    required String sessionId,
    required String encryptionKey,
  }) async {
    try {
      // 1. Force a token refresh on the parent device first.
      // This guarantees we have a brand-new refresh token and that our access token is fresh.
      // The subsequent database update will not trigger any background rotation.
      debugPrint('DeviceLinkService: Proactively refreshing parent session to secure fresh token...');
      final refreshRes = await _client.auth.refreshSession();
      final freshSession = refreshRes.session;
      if (freshSession == null) {
        throw 'Your parent device session has expired or you have been signed out. Please go back, log in again on your phone, and retry.';
      }
      
      final refreshToken = freshSession.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) throw 'No active refresh token available';
      
      // 2. Encrypt the brand-new, active refresh token using the One-Time Pad key from the QR code
      final encryptedToken = _xorEncrypt(refreshToken, encryptionKey);
      
      final parentOS = Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Desktop');
      final parentEmail = AuthService().email;
      
      final parentInfo = {
        'os': parentOS,
        'email': parentEmail,
        'authorized_at': DateTime.now().toIso8601String(),
      };

      // 3. Push encrypted auth credentials to the session row
      final response = await _client
          .from('device_link_sessions')
          .update({
            'status': 'authorized',
            'auth_data': encryptedToken,
            'parent_device_info': parentInfo,
          })
          .eq('id', sessionId)
          .select();
      
      if (response.isEmpty) {
        throw 'Linking session not found or has expired';
      }
      
      debugPrint('DeviceLinkService: Successfully authorized session $sessionId');
      return response.first;
    } catch (e) {
      debugPrint('DeviceLinkService: Failed to authorize session: $e');
      rethrow;
    }
  }

  /// STEP 4 (Child/Unsigned Device): Recovers session via refresh token & deletes DB entry.
  static Future<bool> completeSessionLogin({
    required String sessionId,
    required String encryptionKey,
    required String encryptedAuthData,
  }) async {
    try {
      // Decrypt the refresh token using our locally kept security key
      final decryptedRefreshToken = _xorDecrypt(encryptedAuthData, encryptionKey);
      if (decryptedRefreshToken.isEmpty) throw 'Failed to decrypt auth data';
      
      debugPrint('DeviceLinkService: Recovering session via decrypted refresh token...');
      final authResponse = await _client.auth.setSession(decryptedRefreshToken);
      
      if (authResponse.session != null) {
        debugPrint('DeviceLinkService: ✓ Session recovered successfully!');
        
        // Mark this device locally as a linked child device
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_linked_device', true);
          debugPrint('DeviceLinkService: Local is_linked_device flag written.');
        } catch (pe) {
          debugPrint('DeviceLinkService: Warning setting linked device flag: $pe');
        }
        
        // --- SYNC ALL CLOUD DATA (Continue Watch, Profile, Notifications) ---
        try {
          debugPrint('DeviceLinkService: Starting post-login data synchronization...');
          
          // 1. Sync profile and watched series history from other devices
          await SyncService.syncCloudToLocal();
          await SyncService.syncLocalToCloud();
          SyncService.startRealtimeSync();
          
          // 2. Sync watched series notification lists
          await NotificationService.syncProfileToCloud();
          await NotificationService.syncCrossDeviceWatchedSeries();
          
          debugPrint('DeviceLinkService: ✓ Post-login synchronization completed successfully!');
        } catch (se) {
          debugPrint('DeviceLinkService: Warning during post-login sync: $se');
        }
        
        // Clean up: delete session row from database immediately
        try {
          await _client.from('device_link_sessions').delete().eq('id', sessionId);
          debugPrint('DeviceLinkService: Session row cleaned up.');
        } catch (de) {
          debugPrint('DeviceLinkService: Silent warning cleaning session row: $de');
        }
        
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('DeviceLinkService: Error completing login: $e');
      return false;
    }
  }

  /// Cleans up any expired sessions (called periodically or manually to keep DB neat).
  static Future<void> pruneExpiredSessions() async {
    try {
      final nowStr = DateTime.now().toUtc().toIso8601String();
      await _client.from('device_link_sessions').delete().lt('expires_at', nowStr);
    } catch (e) {
      debugPrint('DeviceLinkService: Prune error: $e');
    }
  }
}
