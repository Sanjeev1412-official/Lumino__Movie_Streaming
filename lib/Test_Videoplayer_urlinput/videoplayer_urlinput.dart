import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player player;
  late final VideoController controller;

  final urlController = TextEditingController();
  bool isPlaying = false;
  String? lastError;

  @override
  void initState() {
    super.initState();

    player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.debug, // 🔥 important
      ),
    );

    controller = VideoController(player);

    // listen for player errors
    player.stream.error.listen((e) {
      debugPrint("PLAYER ERROR: $e");
      setState(() => lastError = e.toString());
    });

    // listen for mpv logs
    player.stream.log.listen((log) {
      debugPrint("MPV ${log.level}: ${log.text}");
    });
  }

  @override
  void dispose() {
    player.dispose();
    urlController.dispose();
    super.dispose();
  }

  Future<void> playUrl() async {
    final url = urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      isPlaying = true;
      lastError = null;
    });

    debugPrint("OPENING URL:");
    debugPrint(url);

    await player.open(
      Media(
        url,
        httpHeaders: {
          // 🔴 critical headers for hostile hls
          "Referer": "https://net51.cc/",
          "Origin": "https://net51.cc",
          "User-Agent":
              "Mozilla/5.0 (Linux; Android 13; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
          "Accept": "*/*",
          "Accept-Encoding": "gzip, deflate, br",
          "Connection": "keep-alive",
          "Cookie": "hd=on; ott=nf",
        },
      ),
      play: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: const [
                  Icon(Icons.play_circle_fill, size: 28),
                  SizedBox(width: 8),
                  Text(
                    "mediakit player",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // video container
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        Container(
                          color: Colors.black,
                          child: isPlaying
                              ? Video(
                                  controller: controller,
                                  fit: BoxFit.cover,
                                )
                              : const Center(
                                  child: Text(
                                    "enter a video url",
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                        ),

                        // tap play / pause
                        if (isPlaying)
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: () {
                                player.state.playing
                                    ? player.pause()
                                    : player.play();
                              },
                              child: Container(
                                alignment: Alignment.center,
                                color: Colors.transparent,
                                child: StreamBuilder<bool>(
                                  stream: player.stream.playing,
                                  builder: (context, snapshot) {
                                    final playing = snapshot.data ?? false;
                                    return AnimatedOpacity(
                                      opacity: playing ? 0.0 : 1.0,
                                      duration:
                                          const Duration(milliseconds: 250),
                                      child: Icon(
                                        playing
                                            ? Icons.pause_circle
                                            : Icons.play_circle,
                                        size: 72,
                                        color: Colors.white70,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // error display (debug only)
            if (lastError != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  lastError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),

            // glass input bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: urlController,
                            style: const TextStyle(fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: "paste video url (mp4 / m3u8)",
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: playUrl,
                          icon: const Icon(Icons.arrow_forward_ios),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
