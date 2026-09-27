import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;

  final LocalAuthentication _auth = LocalAuthentication();
  static const String _keyBiometricEnabled = 'lumino_biometric_lock_enabled';

  final ValueNotifier<bool> isBiometricsEnabledNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLockedNotifier = ValueNotifier<bool>(false);

  bool get isBiometricsEnabled => isBiometricsEnabledNotifier.value;
  bool get isLocked => isLockedNotifier.value;

  BiometricService._internal() {
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_keyBiometricEnabled) ?? false;
      isBiometricsEnabledNotifier.value = enabled;
      if (enabled) {
        // App starts in locked state if enabled
        isLockedNotifier.value = true;
      }
    } catch (e) {
      debugPrint('[BiometricService] Init error: $e');
    }
  }

  /// Check if the device hardware supports biometrics or device credentials (PIN/pattern/passcode)
  Future<bool> isDeviceSupported() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return isSupported || canCheck;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] isDeviceSupported error: $e');
      return false;
    } catch (e) {
      debugPrint('[BiometricService] isDeviceSupported unexpected: $e');
      return false;
    }
  }

  /// Check available biometric types (fingerprint, face, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('[BiometricService] getAvailableBiometrics error: $e');
      return [];
    }
  }

  /// Prompt authentication using fingerprint, Face ID, PIN, pattern, or password.
  Future<bool> authenticate({String? localizedReason}) async {
    try {
      final success = await _auth.authenticate(
        localizedReason: localizedReason ??
            'Unlock Lumino with fingerprint, Face ID, PIN, pattern, or password',
        biometricOnly: false, // allows PIN/pattern/password fallback
        persistAcrossBackgrounding: true,
      );

      if (success) {
        isLockedNotifier.value = false;
      }
      return success;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] PlatformException: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[BiometricService] Auth error: $e');
      return false;
    }
  }

  /// Toggle lock on or off with live verification
  Future<bool> setBiometricEnabled(bool enable) async {
    if (enable) {
      // Check device support first
      final supported = await isDeviceSupported();
      if (!supported && !Platform.isWindows) {
        return false;
      }

      // Verify credentials before enabling
      final authenticated = await authenticate(
        localizedReason:
            'Confirm fingerprint, face ID, PIN, pattern, or password to enable app lock',
      );
      if (!authenticated) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyBiometricEnabled, true);
      isBiometricsEnabledNotifier.value = true;
      return true;
    } else {
      // Verify credentials before disabling security
      final authenticated = await authenticate(
        localizedReason:
            'Confirm your identity to turn off biometric lock',
      );
      if (!authenticated) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyBiometricEnabled, false);
      isBiometricsEnabledNotifier.value = false;
      isLockedNotifier.value = false;
      return true;
    }
  }

  void lockApp() {
    if (isBiometricsEnabled) {
      isLockedNotifier.value = true;
    }
  }

  void unlockApp() {
    isLockedNotifier.value = false;
  }
}
