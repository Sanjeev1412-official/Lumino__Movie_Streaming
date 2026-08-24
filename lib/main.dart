import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:window_manager/window_manager.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'package:lumino_app_moviestreaming/splashscreen.dart';
import 'package:lumino_app_moviestreaming/auth_service.dart';
import 'package:lumino_app_moviestreaming/config/env_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart'; // <-- ADD THIS

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main(List<String> args) async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize environment variables from .env
    await EnvConfig.init();

    // Log all errors
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Flutter Error: ${details.exception}');
    };
  
  // Initialize Supabase with error handling and timeout
  try {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
    ).timeout(const Duration(seconds: 8), onTimeout: () {
      debugPrint('Supabase initialization timed out');
      return Supabase.instance; // Return instance to continue
    });
  } catch (e) {
    debugPrint('Supabase initialization failed: $e');
  }

  // Initialize Firebase core on mobile devices
  if (!Platform.isWindows) {
    try {
      await Firebase.initializeApp();
      debugPrint('Firebase Core successfully initialized on mobile.');
    } catch (e) {
      debugPrint('Firebase Core initialization failed: $e');
    }
  }

  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      "lumino_streaming_app_instance",
      onSecondWindow: (newArgs) async {
        debugPrint('Second instance args: $newArgs');
        // Bring the main window to front first
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}

        // Small delay to let the app fully resume before processing the auth URL
        await Future.delayed(const Duration(milliseconds: 300));

        for (final arg in newArgs) {
          final trimmed = arg.replaceAll('"', '').trim();
          if (trimmed.startsWith('io.supabase.lumino') || trimmed.startsWith('lumino://')) {
            debugPrint('Deep link received from second instance: $trimmed');
            AuthService().onProtocolUrlReceived(trimmed);
            break;
          }
        }
      },
    );

    // Handle deep link from initial launch args
    debugPrint('App launched with args: $args');
    for (final arg in args) {
      final trimmed = arg.replaceAll('"', '').trim();
      if (trimmed.startsWith('io.supabase.lumino') || trimmed.startsWith('lumino://')) {
        debugPrint('Deep link in launch args: $trimmed');
        // Delay needed so Supabase & AuthService are fully initialized
        Future.delayed(const Duration(milliseconds: 500), () {
          AuthService().onProtocolUrlReceived(trimmed);
        });
        break;
      }
    }
  }

  // Orientation and UI mode moved to SplashScreen
  // MediaKit and DownloadManager init moved to SplashScreen
  
  // If you really need to bypass certs in DEV ONLY:
  HttpOverrides.global = DevHttpOverrides();

  //windowmanager init only if platform is window application
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    
    if (Platform.isWindows) {
      // Register custom protocols for Windows
      await protocolHandler.register('io.supabase.lumino');
      await protocolHandler.register('lumino');
    }
  }

    runApp(const MyApp());
  }, (error, stack) {
    debugPrint('Zoned Error: $error');
    debugPrint('Stack: $stack');
  });
}

class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // WARNING: This blindly trusts ALL certificates.
    // Do NOT ship this in production builds.
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Movies',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color.fromARGB(255, 17, 17, 17),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5D4),
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

