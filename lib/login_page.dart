import 'package:flutter/material.dart';
import 'package:lumino_app_moviestreaming/auth_service.dart';
import 'package:lumino_app_moviestreaming/toast.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lumino_app_moviestreaming/device_link_service.dart';
import 'dart:async';
import 'dart:ui';
import 'package:hugeicons/hugeicons.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  String _appVersion = 'v1.3.3';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = 'v${info.version}');
      }
    } catch (_) {}
  }

  Future<void> _handleAuth() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty || (_isSignUp && name.isEmpty)) {
      AppToast.show(
        context,
        'Please fill all fields',
        icon: Icons.warning_amber_rounded,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isSignUp) {
        await AuthService().signUp(
          email: email,
          password: password,
          name: name,
        );
        if (mounted) {
          AppToast.show(
            context,
            'Account created! Please check your email.',
            icon: Icons.email_outlined,
          );
          setState(() => _isSignUp = false);
        }
      } else {
        await AuthService().signIn(email: email, password: password);
        if (mounted) {
          Navigator.pop(context);
          AppToast.show(
            context,
            'Welcome back!',
            icon: Icons.check_circle_outline_rounded,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'Auth Error: $e',
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      // For desktop (Windows), this awaits the entire browser OAuth flow
      // The app will wait here until the browser redirects back with the code
      await AuthService().signInWithGoogle();
      // If we get here, sign-in was successful
      if (mounted) {
        Navigator.pop(context);
        AppToast.show(
          context,
          'Welcome!',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'Google Login Error: $e',
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07080F),
      body: Stack(
        children: [
          // --- CINEMATIC AMBIENT GLOW BACKDROP ---
          Positioned(
            top: -150,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFB561).withValues(alpha: 0.08),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00F0FF).withValues(alpha: 0.04),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          
          // --- MAIN SCROLLABLE CONTENT ---
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Sleek Custom Top Navigation Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 48), // Spacer to balance close button
                      // Center Logo / Branding
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 0, 0, 0),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/icon/app_icon.png',
                              width: 22,
                              height: 22,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'LUMINO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Close button
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Brand Header Text
                  Text(
                    _isSignUp ? 'Create Account' : 'Welcome Back',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.8,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUp
                        ? 'Join Lumino for the best streaming experience'
                        : 'Sign in to continue your cinematic journey',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),

                  // Glassmorphic Login Card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.015),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          children: [
                            if (_isSignUp) ...[
                              _buildTextField(
                                'Full Name',
                                HugeIcons.strokeRoundedUser,
                                _nameController,
                              ),
                              const SizedBox(height: 18),
                            ],
                            _buildTextField(
                              'Email Address',
                              HugeIcons.strokeRoundedMailAtSign01,
                              _emailController,
                            ),
                            const SizedBox(height: 18),
                            _buildTextField(
                              'Password',
                              HugeIcons.strokeRoundedLockKey,
                              _passwordController,
                              isPassword: true,
                            ),
                            const SizedBox(height: 28),
                            
                            // High-end Gradient Action Button
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFFB561), Color(0xFFFF8A00)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFB561).withValues(alpha: 0.2),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _handleAuth,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.black,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          _isSignUp ? 'Sign Up' : 'Sign In',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            
                            // Switch Login State Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isSignUp
                                      ? 'Already have an account? '
                                      : "Don't have an account? ",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() => _isSignUp = !_isSignUp),
                                  child: const Text(
                                    'Switch',
                                    style: TextStyle(
                                      color: Color(0xFFFFB561),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  
                  // Decorative Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.06))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR CONTINUE WITH',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.06))),
                    ],
                  ),
                  const SizedBox(height: 28),
                  
                  // Google Sign-In Option
                  _buildSocialButton(
                    'Continue with Google',
                    'https://www.google.com/favicon.ico',
                  ),
                  const SizedBox(height: 16),
                  
                  // TV/Tablet QR Pairing Option
                  _buildLinkDeviceButton(),
                  
                  const SizedBox(height: 60),
                  Text(
                    'Lumino Streaming $_appVersion',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.18),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String hint,
    dynamic icon,
    TextEditingController controller, {
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1.0,
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 12.0),
            child: HugeIcon(icon: icon, color: Colors.white54, size: 20),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton(String label, String iconUrl) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          backgroundColor: Colors.white.withValues(alpha: 0.01),
        ),
        child: _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white54,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Waiting for browser...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  //add image icon "https://www.google.com/favicon.ico"
                  Image.network(
                    "https://cdn-icons-png.flaticon.com/128/281/281764.png",
                    width: 19,
                    height: 19,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),const SizedBox(width: 12),
                ],
              ),
      ),
    );
  }

  Widget _buildLinkDeviceButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _showQrCodeLinkDialog,
        icon: HugeIcon(icon: HugeIcons.strokeRoundedQrCode, color: const Color(0xFFFFB561), size: 20),
        label: const Text(
          'Link Device via QR Code',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: const Color(0xFFFFB561).withValues(alpha: 0.2), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          backgroundColor: const Color(0xFFFFB561).withValues(alpha: 0.01),
        ),
      ),
    );
  }

  void _showQrCodeLinkDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (dialogCtx, animation, secondaryAnimation) {
        return Center(
          child: _QrCodeDialogContent(
            onLoginSuccess: () {
              Navigator.pop(dialogCtx); // Close Dialog
              Navigator.pop(context);   // Close Login Page
              AppToast.show(
                context,
                '✓ Signed in successfully via QR!',
                icon: Icons.check_circle_outline_rounded,
              );
            },
            onCancel: () {
              Navigator.pop(dialogCtx);
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curve,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }
}

class _QrCodeDialogContent extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  final VoidCallback onCancel;

  const _QrCodeDialogContent({
    required this.onLoginSuccess,
    required this.onCancel,
  });

  @override
  State<_QrCodeDialogContent> createState() => _QrCodeDialogContentState();
}

class _QrCodeDialogContentState extends State<_QrCodeDialogContent> {
  String? _qrPayload;
  String? _sessionId;
  String? _encryptionKey;
  bool _isLoading = true;
  bool _isCompleting = false;
  String? _error;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startSession() async {
    try {
      final session = await DeviceLinkService.initiateLinkSession();
      if (!mounted) return;
      
      setState(() {
        _qrPayload = session['qrPayload'];
        _sessionId = session['sessionId'];
        _encryptionKey = session['encryptionKey'];
        _isLoading = false;
      });

      _subscription = DeviceLinkService.listenToSession(_sessionId!).listen((record) async {
        if (record['status'] == 'authorized') {
          final authData = record['auth_data'] as String?;
          if (authData != null && mounted) {
            setState(() => _isCompleting = true);
            final success = await DeviceLinkService.completeSessionLogin(
              sessionId: _sessionId!,
              encryptionKey: _encryptionKey!,
              encryptedAuthData: authData,
            );
            if (success) {
              widget.onLoginSuccess();
            } else {
              setState(() {
                _isCompleting = false;
                _error = 'Failed to recover login session';
              });
            }
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to initiate linking: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 360,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0D12).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB561).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.devices_rounded,
                              color: Color(0xFFFFB561),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Link Device',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: widget.onCancel,
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.4),
                          size: 22,
                        ),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  
                  // Clean Instructions Panel
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildInstructionRow('1', 'Open Lumino on your signed-in phone'),
                        const SizedBox(height: 10),
                        _buildInstructionRow('2', 'Go to Profile -> Link a Device'),
                        const SizedBox(height: 10),
                        _buildInstructionRow('3', 'Scan the QR code to sign in instantly'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Stylish Dotted QR Code with center app play-logo icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFFFB561),
                              ),
                            )
                          : _error != null
                              ? Center(
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Custom styled white QR Code
                                    QrImageView(
                                      data: _qrPayload!,
                                      version: QrVersions.auto,
                                      size: 200.0,
                                      gapless: false,
                                      eyeStyle: QrEyeStyle(
                                        eyeShape: QrEyeShape.circle,
                                        color: Colors.white,
                                      ),
                                      dataModuleStyle: QrDataModuleStyle(
                                        dataModuleShape: QrDataModuleShape.circle,
                                        color: Colors.white.withValues(alpha: 0.9),
                                      ),
                                    ),
                                    
                                    // Center Brand Logo Overlay
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0C0D12),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.15),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFFB561).withValues(alpha: 0.3),
                                            blurRadius: 12,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(2), // Clean padding for app icon
                                      child: ClipOval(
                                        child: Image.asset(
                                          'assets/icon/app_icon.png',
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bottom State
                  if (_isCompleting) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFFFFB561),
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Linking authorized! Signing in...',
                      style: TextStyle(
                        color: Color(0xFFFFB561),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: Colors.white.withValues(alpha: 0.3),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Expires in 5 minutes',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionRow(String number, String text) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFFFFB561).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFFFFB561),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
