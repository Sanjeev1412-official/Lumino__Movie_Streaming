import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized configuration provider for environment variables and secrets.
/// Reads from `.env` loaded via `flutter_dotenv` with fallback to `--dart-define` constants.
class EnvConfig {
  static bool _isInitialized = false;

  /// Initializes the environment configuration by loading the `.env` asset file.
  static Future<void> init() async {
    if (_isInitialized) return;
    try {
      await dotenv.load(fileName: ".env");
      _isInitialized = true;
      debugPrint("EnvConfig: Successfully loaded .env configuration.");
    } catch (e) {
      debugPrint("EnvConfig: Warning - Could not load .env file: $e. Falling back to dart-define environment.");
    }
  }

  /// AWS Lambda Base URL for Movie/Series APIs
  static String get lambdaUrl {
    final val = dotenv.env['LAMBDA_BASE_URL'];
    if (val != null && val.isNotEmpty) return val;
    return const String.fromEnvironment('LAMBDA_BASE_URL', defaultValue: '');
  }

  /// TMDB API Key
  static String get tmdbApiKey {
    final val = dotenv.env['TMDB_API_KEY'];
    if (val != null && val.isNotEmpty) return val;
    return const String.fromEnvironment('TMDB_API_KEY', defaultValue: '');
  }

  /// Supabase Project URL
  static String get supabaseUrl {
    final val = dotenv.env['SUPABASE_URL'];
    if (val != null && val.isNotEmpty) return val;
    return const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  }

  /// Supabase Public Anonymous API Key
  static String get supabaseAnonKey {
    final val = dotenv.env['SUPABASE_ANON_KEY'];
    if (val != null && val.isNotEmpty) return val;
    return const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  }

  /// Lumino Render Backend URL (Magnet / Stream Resolver)
  static String get luminoBackendUrl {
    final val = dotenv.env['LUMINO_BACKEND_URL'];
    if (val != null && val.isNotEmpty) return val;
    return const String.fromEnvironment('LUMINO_BACKEND_URL', defaultValue: 'https://lumino-backend-cnmu.onrender.com');
  }

  /// Live TV Backend API URL
  static String get liveTvApiUrl {
    final val = dotenv.env['LIVETV_API_URL'];
    if (val != null && val.isNotEmpty) return val;
    return const String.fromEnvironment('LIVETV_API_URL', defaultValue: 'https://sanjeev1412-livetv-api.hf.space');
  }
}
