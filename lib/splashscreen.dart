import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:lumino_app_moviestreaming/download_hud.dart';
import 'package:lumino_app_moviestreaming/homescreen.dart';
import 'package:media_kit/media_kit.dart';
import 'package:lumino_app_moviestreaming/notification_service.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this);
    _fallbackTimer = Timer(const Duration(seconds: 10), _goNext);

    // Initialize services here once
    _initServices();
    
    // Start prefetching Hero logos in the background while splash is showing
    MovieHomePage.prefetchHeroLogos();
  }

  Future<void> _initServices() async {
    try {
      MediaKit.ensureInitialized();
      DownloadManager().init();
      await NotificationService.init();
    } catch (e) {
      debugPrint('Service Init Error: $e');
    }
  }

  void _goNext() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => const MovieHomePage(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Set UI mode once the widget tree is building
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
    ]);

    return Scaffold(
      backgroundColor: Colors.black, // PURE BLACK
      body: Stack(
        children: [
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 900,
                height: 900,
                child: Lottie.asset(
                  'assets/animations/splash.json',
                  controller: _controller,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Splash Lottie Error: $error');
                    return const Center(
                      child: Icon(Icons.play_circle_fill, color: Colors.cyan, size: 100),
                    );
                  },
                  onLoaded: (composition) {
                    _controller
                      ..duration = composition.duration
                      ..forward();

                    _controller.addStatusListener((status) {
                      if (status == AnimationStatus.completed) {
                        _fallbackTimer?.cancel();
                        _goNext();
                      }
                    });
                  },
                ),
              ),
            ),
          ),
          
        ],
      ),
    );
  }
}
