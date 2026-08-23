import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:lumino_app_moviestreaming/auth_service.dart';
import 'package:lumino_app_moviestreaming/login_page.dart';
import 'package:lumino_app_moviestreaming/profile_page.dart';

class ProfileButton extends StatelessWidget {
  final VoidCallback? onTapUpdate;
  const ProfileButton({super.key, this.onTapUpdate});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService(),
      builder: (context, child) {
        final auth = AuthService();
        if (!auth.isLoggedIn) {
          return IconButton(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedUserCircle,
              color: Colors.white70,
              size: 21.0,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          );
        }

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => ProfilePage(onTapUpdate: onTapUpdate),
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
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color.fromARGB(100, 255, 255, 255), Color.fromARGB(50, 255, 255, 255)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              
            ),
            child: Padding(
              padding: const EdgeInsets.all(1.5),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromARGB(255, 37, 37, 37),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: Hero(
                    tag: 'profile-avatar',
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: auth.avatarUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFFFFB561)),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: HugeIcon(icon: HugeIcons.strokeRoundedUser, color: Color(0xFFFFB561), size: 18.0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}