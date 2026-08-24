// ignore_for_file: dead_code, dead_null_aware_expression, invalid_use_of_protected_member, unused_element
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'details.dart';
import 'toast.dart';
import 'moviebox_service.dart';
import 'package:lumino_app_moviestreaming/config/env_config.dart';

class SearchPage extends StatefulWidget {
  final String apiKey;
  final String base;
  final String imgW185;
  final String imgW500;
  final String imgW780;
  final String? initialQuery;

  const SearchPage({
    super.key,
    required this.apiKey,
    required this.base,
    required this.imgW185,
    required this.imgW500,
    required this.imgW780,
    this.initialQuery,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;

  bool _loading = false;
  bool _navigating = false;
  String _query = '';
  List<MovieBoxItem> _media = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    
    _searchFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _debounce?.cancel();
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    if (widget.initialQuery != null) {
      _controller.text = widget.initialQuery!;
      _query = widget.initialQuery!;
      _search(_query);
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  bool _focusRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Safely request focus exactly when the page transition animation completes
    ModalRoute.of(context)?.animation?.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && !_focusRequested) {
        _focusRequested = true;
        _searchFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final q = _controller.text.trim();
      if (q.isEmpty) {
        setState(() {
          _query = '';
          _media.clear();
        });
        return;
      }
      _query = q;
      _search(q);
    });
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _loading = true);

    // Always use MovieBox API (primary). Advanced search mode tries TMDB text search as fallback.
    List<MovieBoxItem> results = await MovieBoxService.search(q);

    if (!mounted) return;
    if (_controller.text.trim() != q) return;

    setState(() {
      _media = results;
      _loading = false;
    });
  }

  void setNavigating(bool val) {
    if (mounted) setState(() => _navigating = val);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0D12),
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.fromARGB(255, 7, 7, 7),
                      Color.fromARGB(255, 17, 17, 17),
                    ],
                  ),
                ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _ModernSearchBar(
                  controller: _controller,
                  focusNode: _searchFocusNode,
                ),
                Expanded(
                  child: _query.isEmpty
                      ? const _ModernHint()
                      : Stack(
                          children: [
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: _loading ? 0.6 : 1.0,
                              child: _ModernResults(media: _media, parentState: this),
                            ),
                            if (_loading)
                              const Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(
                                  backgroundColor: Colors.transparent,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFB561)),
                                  minHeight: 2,
                                ),
                              ),
                            if (!_loading && _media.isEmpty)
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 64,
                                      color: Colors.white.withValues(alpha: 0.1),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'No results found',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 40),
                                      child: Text(
                                        "We couldn't find anything matching your query.",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.3),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),

          if (_navigating)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFB561)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModernSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _ModernSearchBar({
    required this.controller,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          _backButton(context),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: const Color(0xFFFFB561),
                    decoration: InputDecoration(
                      hintText: 'Search movies & series...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 15),
                      prefixIcon: Hero(
                        tag: 'search-icon',
                        child: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      suffixIcon: controller.text.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                            onPressed: () => controller.clear(),
                          )
                        : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        height: 54,
        width: 54,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
      ),
    );
  }
}

class _ModernResults extends StatelessWidget {
  final List<MovieBoxItem> media;
  final _SearchPageState parentState;

  const _ModernResults({required this.media, required this.parentState});

  Future<void> _openDetails(BuildContext context, MovieBoxItem item) async {
    if (parentState._navigating) return;
    parentState.setNavigating(true);
    try {
      if (context.mounted) {
        final w = parentState.widget;
        // Navigate directly using the MovieBox subject ID — no TMDB lookup needed
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailsPage(
              apiKey: w.apiKey,
              base: w.base,
              imgW185: w.imgW185,
              imgW500: w.imgW500,
              imgW780: w.imgW780,
              id: 0, // TMDB ID will be resolved inside DetailsPage via MovieBox /details
              mediaType: item.isMovie ? 'movie' : 'tv',
              linkApiBase: EnvConfig.luminoBackendUrl,
              movieboxSubjectId: item.id,
              initialTitle: item.title,
              initialBackdrop: item.poster,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) AppToast.show(context, 'Failed to open details.');
    } finally {
      parentState.setNavigating(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width < 480 ? 3 : (width < 720 ? 4 : (width < 1024 ? 5 : 6));

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              childAspectRatio: 0.64,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final m = media[i];
                return _ModernMediaCard(
                  item: m,
                  onTap: () => _openDetails(context, m),
                );
              },
              childCount: media.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModernMediaCard extends StatelessWidget {
  final MovieBoxItem item;
  final VoidCallback onTap;

  const _ModernMediaCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ratingStr = item.rating ?? '';
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.poster != null && item.poster!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.poster!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: Colors.white.withValues(alpha: 0.05)),
                            errorWidget: (context, url, error) => Container(color: Colors.white10),
                          )
                        : Container(color: Colors.white10),

                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Text(
                          item.isMovie ? 'MOVIE' : 'TV',
                          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white70),
                        ),
                      ),
                    ),

                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.2),
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (ratingStr.isNotEmpty && ratingStr != 'N/A')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, size: 10, color: const Color(0xFFFFB561).withValues(alpha: 0.8)),
                  const SizedBox(width: 2),
                  Text(
                    ratingStr,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModernHint extends StatelessWidget {
  const _ModernHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 64, color: Colors.white.withValues(alpha: 0.05)),
          const SizedBox(height: 16),
          Text(
            'Search for movies or series',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'start typing to discover movies',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}



