import 'package:flutter/material.dart';
import 'package:lumino_app_moviestreaming/biometric_service.dart';

class BiometricLockWrapper extends StatefulWidget {
  final Widget child;

  const BiometricLockWrapper({super.key, required this.child});

  @override
  State<BiometricLockWrapper> createState() => _BiometricLockWrapperState();
}

class _BiometricLockWrapperState extends State<BiometricLockWrapper>
    with WidgetsBindingObserver {
  final BiometricService _biometricService = BiometricService();
  bool _hasPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _biometricService.isLockedNotifier.addListener(_onLockChanged);

    // Initial check on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_biometricService.isBiometricsEnabled && _biometricService.isLocked) {
        _triggerPrompt();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _biometricService.isLockedNotifier.removeListener(_onLockChanged);
    super.dispose();
  }

  void _onLockChanged() {
    if (mounted) {
      setState(() {});
      if (_biometricService.isLocked && !_hasPrompted) {
        _triggerPrompt();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_biometricService.isBiometricsEnabled) {
        _hasPrompted = false;
        _biometricService.lockApp();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_biometricService.isBiometricsEnabled && _biometricService.isLocked) {
        _triggerPrompt();
      }
    }
  }

  Future<void> _triggerPrompt() async {
    if (!_biometricService.isLocked) return;
    _hasPrompted = true;
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted && _biometricService.isLocked) {
      await _biometricService.authenticate();
      _hasPrompted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _biometricService.isLockedNotifier,
      builder: (context, isLocked, _) {
        return Stack(
          children: [
            widget.child,
            if (isLocked)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: BiometricLockScreen(
                    onUnlockRequested: () => _biometricService.authenticate(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class BiometricLockScreen extends StatefulWidget {
  final VoidCallback onUnlockRequested;

  const BiometricLockScreen({super.key, required this.onUnlockRequested});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C0D12),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Glowing biometric icon container
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFB561).withValues(alpha: 0.1),
                        border: Border.all(
                          color: const Color(0xFFFFB561).withValues(alpha: 0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFB561).withValues(alpha: 0.18),
                            blurRadius: 36,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.fingerprint_rounded,
                          size: 54,
                          color: Color(0xFFFFB561),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 36),

              // Title
              const Text(
                'Lumino is Locked',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Unlock the app with fingerprint, face ID,\nPIN, pattern, or password',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 2),

              // Unlock button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: widget.onUnlockRequested,
                  icon: const Icon(Icons.lock_open_rounded, size: 20),
                  label: const Text(
                    'Unlock Now',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB561),
                    foregroundColor: const Color(0xFF0C0D12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
