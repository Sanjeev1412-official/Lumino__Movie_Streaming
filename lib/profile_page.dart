// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lumino_app_moviestreaming/auth_service.dart';
import 'package:lumino_app_moviestreaming/my_downloads_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lumino_app_moviestreaming/qr_scanner_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback? onTapUpdate;
  const ProfilePage({super.key, this.onTapUpdate});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isUpdating = false;
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

  Future<void> _pickAndUploadImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isUpdating = true);
        final file = File(result.files.single.path!);
        final url = await AuthService().uploadAvatar(file);
        if (url != null) {
          await AuthService().updateProfile(avatarUrl: url);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile picture updated successfully')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile picture: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _showEditNameDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171B26),
        title: const Text('Edit Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            hintStyle: TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFB561))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFB561), foregroundColor: Colors.black),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty && newName != currentName) {
      setState(() => _isUpdating = true);
      try {
        await AuthService().updateProfile(name: newName.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Name updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating name: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _openQrScanner(BuildContext context) async {
    final String? linkedDeviceOS = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerPage()),
    );
    
    if (linkedDeviceOS != null && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF171B26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, color: Color(0xFFFFB561)),
              SizedBox(width: 10),
              Text('Device Linked!', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            'You have successfully authorized and linked your account with a new $linkedDeviceOS device.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Great!', style: TextStyle(color: Color(0xFFFFB561))),
            ),
          ],
        ),
      );

      // Await 2 seconds to let the child device complete its setSession operation,
      // and then proactively refresh the parent session. This rotates the parent to a completely
      // independent session branch, keeping both devices fully authenticated with zero conflict!
      Future.delayed(const Duration(seconds: 2), () async {
        try {
          debugPrint('ProfilePage: Proactively rotating parent session post-link...');
          await Supabase.instance.client.auth.refreshSession();
          debugPrint('ProfilePage: Parent session successfully rotated and isolated.');
        } catch (re) {
          debugPrint('ProfilePage: Non-blocking warning rotating parent session: $re');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService(),
      builder: (context, _) {
        final auth = AuthService();
        final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

        return Scaffold(
          backgroundColor: const Color(0xFF0C0D12),
          body: Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildAppBar(context),
                  SliverToBoxAdapter(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutQuart,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),
                            _buildProfileHeader(auth, isDesktop),
                            const SizedBox(height: 24),
                            _buildSectionTitle('CONTENT'),
                            _buildMenuCard([
                              _buildMenuItem(
                                context,
                                icon: HugeIcons.strokeRoundedDownload01,
                                label: 'My Downloads',
                                subtitle: 'View your offline content',
                                onTap: () => Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, secondaryAnimation) => const MyDownloadsPage(),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    const begin = Offset(0.0, 0.05);
                                    const end = Offset.zero;
                                    const curve = Curves.easeOutQuart;
                                    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                    var offsetAnimation = animation.drive(tween);
                                    var fadeAnimation = animation.drive(CurveTween(curve: Curves.easeIn));

                                    return FadeTransition(
                                      opacity: fadeAnimation,
                                      child: SlideTransition(
                                        position: offsetAnimation,
                                        child: child,
                                      ),
                                    );
                                  },
                                  transitionDuration: const Duration(milliseconds: 500),
                                ),
                              ),
                              ),
                            ]),
                            const SizedBox(height: 24),
                            _buildSectionTitle('PREFERENCES'),
                            _buildMenuCard([
                              if (widget.onTapUpdate != null)
                                _buildMenuItem(
                                  context,
                                  icon: HugeIcons.strokeRoundedRefresh,
                                  label: 'Check for Updates',
                                  subtitle: 'Look for new app versions',
                                  onTap: widget.onTapUpdate!,
                                ),
                              _buildMenuItem(
                                context,
                                icon: Icons.qr_code_scanner_rounded,
                                label: 'Link a Device',
                                subtitle: 'Scan QR code to authorize another device',
                                onTap: () => _openQrScanner(context),
                              ),
                              _buildMenuItem(
                                context,
                                icon: HugeIcons.strokeRoundedSettings03,
                                label: 'App Settings',
                                subtitle: 'Theme, language, and more',
                                onTap: () {},
                              ),
                            ]),
                            const SizedBox(height: 24),
                            _buildSectionTitle('DANGER ZONE'),
                            _buildMenuCard([
                              _buildMenuItem(
                                context,
                                icon: HugeIcons.strokeRoundedLogout01,
                                label: 'Sign Out',
                                subtitle: 'Log out of your account',
                                color: Colors.redAccent,
                                onTap: () {
                                  auth.logout();
                                  Navigator.pop(context);
                                },
                              ),
                            ]),
                            const SizedBox(height: 40),
                            Center(
                              child: Text(
                                'Lumino Streaming $_appVersion',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isUpdating)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFB561)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Profile Settings',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
      ),
      centerTitle: true,
    );
  }

  Widget _buildProfileHeader(AuthService auth, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.01),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Hero(
                tag: 'profile-avatar',
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFB561), Color(0xFFFF8A00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFB561).withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: auth.avatarUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const Center(
                        child: HugeIcon(icon: HugeIcons.strokeRoundedUser, color: Colors.white, size: 32.0),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB561),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0C0C0F), width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showEditNameDialog(auth.name),
                        child: Text(
                          auth.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.edit_rounded, size: 18, color: Colors.white.withValues(alpha: 0.3)),
                      onPressed: () => _showEditNameDialog(auth.name),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                Text(
                  auth.email,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: isDesktop ? 14 : 12, fontWeight: FontWeight.w500),
                ),
                
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildMenuCard(List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: items,
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required dynamic icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final iconColor = color ?? Colors.white.withValues(alpha: 0.8);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: icon is IconData
                    ? Icon(icon, size: 22.0, color: iconColor)
                    : HugeIcon(icon: icon as List<List<dynamic>>, size: 22.0, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: iconColor, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white.withValues(alpha: 0.1)),
            ],
          ),
        ),
      ),
    );
  }
}
