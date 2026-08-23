import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lumino_app_moviestreaming/main.dart';
import 'package:lumino_app_moviestreaming/sync_service.dart';
import 'package:lumino_app_moviestreaming/toast.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lumino_app_moviestreaming/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier with ProtocolListener {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    // Listen to Supabase auth changes
    _client.auth.onAuthStateChange.listen((data) async {
      debugPrint('Auth State Changed: ${data.event}');
      
      if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.initialSession) {
        final user = _client.auth.currentUser;
        if (user != null) {
          debugPrint('Auth: Active session for ${user.id}. Syncing profile to database...');
          
          // 1. First, try to RESTORE previous profile from database
          await SyncService.syncCloudToLocal();
          
          // 2. Then, ensure current metadata is BACKED UP to the database
          // This ensures new users or Google logins have their data stored by default
          await SyncService.syncLocalToCloud();
          
          SyncService.startRealtimeSync();
          
          // Link this device's app_user_id with the authenticated user, and sync watched series from other devices
          await NotificationService.syncProfileToCloud();
          await NotificationService.syncCrossDeviceWatchedSeries();
          
          // Sync FCM token with this newly authenticated user
          await NotificationService.syncFcmTokenToCloud();
          
          notifyListeners();
        }
      } else if (data.event == AuthChangeEvent.signedOut) {
        // Unlink the device from the authenticated user on sign out
        await NotificationService.syncProfileToCloud();
      }
      notifyListeners();
    });
    // Listen to SyncService notifications for cross-device profile/history sync
    SyncService.onSyncNotify.stream.listen((_) {
      debugPrint('Auth: Sync notification received, updating UI...');
      notifyListeners();
    });

    // Listen to Windows protocol links
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      protocolHandler.addListener(this);
      _handleInitialUri();
    }
  }

  Future<void> _handleInitialUri() async {
    try {
      final initialUrl = await protocolHandler.getInitialUrl();
      if (initialUrl != null) {
        onProtocolUrlReceived(initialUrl);
      }
    } catch (e) {
      debugPrint('Error handling initial URI: $e');
    }
  }

  @override
  void onProtocolUrlReceived(String url) async {
    debugPrint('Protocol URL received: $url');
    final cleanUrl = url.replaceAll('"', '').trim();

    final uri = Uri.parse(cleanUrl);

    // Check if URL has an auth code or token (PKCE or implicit flow)
    final hasCode = uri.queryParameters.containsKey('code') ||
        Uri.splitQueryString(uri.fragment).containsKey('code');
    final hasToken = cleanUrl.contains('access_token=');

    if (hasCode || hasToken) {
      try {
        if (navigatorKey.currentContext != null) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            const SnackBar(content: Text('Signing you in...'), duration: Duration(seconds: 3)),
          );
        }

        debugPrint('Auth: Exchanging URL for session: $cleanUrl');
        // getSessionFromUrl handles BOTH pkce (code) and implicit (access_token) internally.
        // For PKCE, supabase_flutter looks up the stored code_verifier using the full URL.
        await _client.auth.getSessionFromUrl(uri);
        
        debugPrint('Session successfully updated.');
        
        if (_client.auth.currentSession != null) {
          debugPrint('Login confirmed for: ${_client.auth.currentUser?.email}');
          if (navigatorKey.currentContext != null) {
            ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
              const SnackBar(
                content: Text('✓ Signed in with Google!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          debugPrint('Auth: session still null after getSessionFromUrl');
        }
        
        notifyListeners(); 
      } catch (e) {
        debugPrint('Error getting session from URL: $e');
        if (navigatorKey.currentContext != null) {
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            SnackBar(
              content: Text('Login error: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } else if (cleanUrl.startsWith('lumino://') || cleanUrl.startsWith('io.supabase.lumino://')) {
      // Handle other custom links or redirect links that don't have tokens yet
      debugPrint('Handling custom/redirect link: $cleanUrl');
      
      // Ensure the window is focused when a link is clicked
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        windowManager.show();
        windowManager.focus();
      }

      // Provide visual feedback
      if (navigatorKey.currentContext != null) {
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text('Received: $cleanUrl'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF00E5D4),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (cleanUrl.contains('test')) {
        debugPrint('Test protocol link triggered successfully!');
      }
    }
  }

  final SupabaseClient _client = Supabase.instance.client;

  // Getters
  bool get isLoggedIn => _client.auth.currentSession != null;
  User? get user => _client.auth.currentUser;

  String get name => user?.userMetadata?['full_name'] ?? user?.email?.split('@')[0] ?? 'User';
  String get email => user?.email ?? '';
  String get avatarUrl => user?.userMetadata?['avatar_url'] ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=random';

  // --- Actions ---

  Future<AuthResponse> signUp({required String email, required String password, required String name}) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name},
    );
  }

  Future<AuthResponse> signIn({required String email, required String password}) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signInWithGoogle() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      // --- Mobile / Web: use google_sign_in plugin ---
      const webClientId = '779206739350-b9n7044rsm8vjv0s954de1mnepo70nq5.apps.googleusercontent.com';
      const iosClientId = '877812764303-q4974pmlc553v018vutn2dqs9s4f909o.apps.googleusercontent.com';

      await GoogleSignIn.instance.initialize(
        clientId: iosClientId,
        serverClientId: webClientId,
      );
      final googleUser = await GoogleSignIn.instance.authenticate();

      final authResult = await googleUser.authorizationClient.authorizeScopes(['email', 'openid']);
      final accessToken = authResult.accessToken;
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) throw 'Missing Google ID Token';

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } else {
      // --- Windows / Linux / macOS: Localhost redirect server ---
      await _signInWithGoogleDesktop();
    }
  }

  /// Opens a temporary local HTTP server, launches Google OAuth in the browser,
  /// catches the redirect with the auth code, and exchanges it for a session.
  /// This is the most reliable desktop OAuth method (used by VS Code, etc.)
  Future<void> _signInWithGoogleDesktop() async {
    HttpServer? server;
    try {
      // 1. Use a FIXED port so you can add it to Supabase redirect allowlist
      // If 54321 is taken, it will throw an error, which is better than a random port failing silently at Supabase
      const int fixedPort = 54321;
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, fixedPort);
      } catch (e) {
        debugPrint('🔐 Auth: Port $fixedPort taken, falling back to random port (Note: This may fail Supabase allowlist)');
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      }
      
      final port = server.port;
      final redirectUrl = 'http://localhost:$port/callback';
      debugPrint('🔐 Auth: Started local callback server on port $port');
      debugPrint('🔐 Auth: Redirect URL = $redirectUrl');

      // 2. Generate the Supabase OAuth URL with localhost as redirect
      final oauthResponse = await _client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: redirectUrl,
        scopes: 'email profile openid',
      );
      debugPrint('🔐 Auth: OAuth URL generated: ${oauthResponse.url}');

      // 3. Open the browser
      final launched = await launchUrl(
        Uri.parse(oauthResponse.url),
        mode: LaunchMode.externalApplication,
      );
      debugPrint('🔐 Auth: Browser launched: $launched');
      if (!launched) throw 'Could not open browser for Google Sign-In';

      // 4. Show feedback
      _showSnack('Opening Google Sign-In in browser...');

      // 5. Wait for the browser to redirect back (timeout after 3 minutes)
      String? authCode;
      final completer = Completer<void>();
      final subscription = server.listen((request) async {
        debugPrint('🔐 Auth: Received request: ${request.uri}');
        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];

        request.response.headers.contentType = ContentType.html;
        request.response.statusCode = 200;
        if (error != null) {
          debugPrint('🔐 Auth: OAuth error from provider: $error');
          request.response.write('''
            <html><head><title>Lumino - Sign In Error</title>
            <style>body{background:#141414;color:white;font-family:sans-serif;
            display:flex;align-items:center;justify-content:center;height:100vh;margin:0;}</style></head>
            <body><h2 style="color:red">Sign-In Error: $error</h2><p>Please return to Lumino and try again.</p></body></html>
          ''');
        } else {
          request.response.write('''
            <html><head><title>Lumino - Sign In</title>
            <style>body{background:#141414;color:white;font-family:sans-serif;
            display:flex;align-items:center;justify-content:center;height:100vh;margin:0;}
            .box{text-align:center;padding:40px;border-radius:16px;
            background:#1e1e1e;border:1px solid #333;}</style></head>
            <body><div class="box">
            <h2 style="color:#FFB561">✓ Sign-In Successful!</h2>
            <p>You can close this tab and return to Lumino.</p>
            </div></body></html>
          ''');
        }
        await request.response.close();

        if (code != null && !completer.isCompleted) {
          debugPrint('🔐 Auth: Got auth code (length ${code.length}), completing...');
          authCode = code;
          completer.complete();
        } else if (error != null && !completer.isCompleted) {
          completer.completeError('OAuth error: $error');
        }
      });

      // Wait for code or timeout after 3 minutes
      await completer.future.timeout(const Duration(minutes: 3)).catchError((e) {
        debugPrint('🔐 Auth: Timeout or error waiting for code: $e');
      });
      await subscription.cancel();

      if (authCode == null) throw 'No auth code received (check Supabase redirect URL allowlist: http://localhost)';

      debugPrint('🔐 Auth: Exchanging code for session...');

      // 6. Exchange the code for a Supabase session
      await _client.auth.exchangeCodeForSession(authCode!);

      if (_client.auth.currentSession != null) {
        debugPrint('🔐 Auth: ✓ Signed in as ${_client.auth.currentUser?.email}');
        // We let the calling UI (LoginPage) handle the success toast
        // Bring the app window back to front
        try { windowManager.show(); windowManager.focus(); } catch(_) {}
        notifyListeners();
      } else {
        throw 'Session not established after code exchange';
      }
    } catch (e) {
      debugPrint('🔐 Auth: Google Sign-In error: $e');
      _showSnack('Sign-In failed: $e', isError: true);
      rethrow;
    } finally {
      await server?.close(force: true);
      debugPrint('🔐 Auth: Local callback server closed.');
    }
  }

  void _showSnack(String message, {bool isSuccess = false, bool isError = false}) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    AppToast.show(
      ctx,
      message,
      icon: isSuccess
          ? Icons.check_circle_outline_rounded
          : isError
              ? Icons.error_outline_rounded
              : Icons.info_outline_rounded,
      tag: isSuccess ? 'Success' : isError ? 'Error' : 'Auth',
    );
  }

  Future<void> logout() async {
    SyncService.stopRealtimeSync();
    
    // Unlink FCM token from user while still logged in
    await NotificationService.unlinkFcmTokenFromUser();
    
    // Check if this device is a linked child device
    bool isLinked = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      isLinked = prefs.getBool('is_linked_device') ?? false;
    } catch (_) {}

    final List<Future> futures = [_client.auth.signOut()];
    
    // GoogleSignIn.signOut is only implemented for Web, Android, and iOS.
    // Calling it on Desktop (Windows/Linux) triggers an UnimplementedError.
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      try {
        futures.add(GoogleSignIn.instance.signOut());
      } catch (e) {
        debugPrint('Error signing out from Google: $e');
      }
    }

    await Future.wait(futures);
    
    // If it is a linked child device, completely wipe all local preferences to start 100% fresh!
    if (isLinked) {
      debugPrint('Auth: Linked child device signing out. Performing complete local storage wipe...');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        debugPrint('Auth: Local storage wiped successfully.');
      } catch (ce) {
        debugPrint('Auth: Error clearing local storage: $ce');
      }
    }
    
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? avatarUrl}) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['full_name'] = name;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    if (updates.isNotEmpty) {
      await _client.auth.updateUser(UserAttributes(data: updates));
      // Trigger immediate sync to push changes to 'user_sync_data' table
      await SyncService.syncLocalToCloud();
      notifyListeners();
    }
  }

  Future<String?> uploadAvatar(File file) async {
    final userId = user?.id;
    if (userId == null) throw 'User not logged in';

    // 1. Check file size (10 MB = 10 * 1024 * 1024 bytes)
    final int sizeInBytes = await file.length();
    const int maxSize = 10 * 1024 * 1024;
    if (sizeInBytes > maxSize) {
      throw 'File too large. Maximum size is 10 MB.';
    }

    final fileExt = file.path.split('.').last.toLowerCase();
    // Use a clean path: userId/timestamp.ext
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final filePath = '$userId/$fileName';

    try {
      debugPrint('Uploading avatar to storage: $filePath');
      await _client.storage.from('avatars').upload(
            filePath,
            file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      final imageUrl = _client.storage.from('avatars').getPublicUrl(filePath);
      debugPrint('Avatar uploaded successfully: $imageUrl');
      return imageUrl;
    } on StorageException catch (e) {
      if (e.statusCode == '403') {
        throw 'Access Denied (403): Please ensure your Supabase storage policies for the "avatars" bucket allow authenticated uploads.';
      }
      throw 'Storage Error: ${e.message}';
    } catch (e) {
      throw 'Upload failed: $e';
    }
  }
}
