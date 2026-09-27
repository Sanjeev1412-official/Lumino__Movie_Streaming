// ignore_for_file: dead_code, dead_null_aware_expression, invalid_use_of_protected_member, unused_element
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'details.dart';
import 'toast.dart';
import 'moviebox_service.dart';
import 'package:lumino_app_moviestreaming/config/env_config.dart';
import 'package:lumino_app_moviestreaming/layout_settings_service.dart';

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

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;

  late final AnimationController _openAnimationController;
  late final Animation<double> _openFadeAnimation;
  late final Animation<Offset> _searchBarSlideAnimation;
  late final Animation<Offset> _bodySlideAnimation;
  late final Animation<double> _bodyFadeAnimation;

  bool _loading = false;
  bool _navigating = false;
  String _query = '';
  List<MovieBoxItem> _media = [];

  // Modern structure controls:
  String _selectedFilter = 'all'; // 'all' | 'movie' | 'series'
  bool _isGridView = true; // true: modern grid, false: detailed list

  List<MovieBoxItem> get _filteredMedia {
    if (_selectedFilter == 'movie') {
      return _media.where((m) => m.isMovie).toList();
    } else if (_selectedFilter == 'series') {
      return _media.where((m) => !m.isMovie).toList();
    }
    return _media;
  }

  int get _moviesCount => _media.where((m) => m.isMovie).length;
  int get _seriesCount => _media.where((m) => !m.isMovie).length;

  static List<TmdbTrendingTopic> _cachedTrendingTopics = [];
  List<TmdbTrendingTopic> _trendingTopics = [];
  bool _loadingTrending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);

    if (_cachedTrendingTopics.isNotEmpty) {
      _trendingTopics = List.from(_cachedTrendingTopics);
    }
    _fetchTrendingTopics();

    _searchFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _debounce?.cancel();
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _controller.text = widget.initialQuery!;
      _query = widget.initialQuery!;
      _search(_query);
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }

    _openAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _openFadeAnimation = CurvedAnimation(
      parent: _openAnimationController,
      curve: Curves.easeOut,
    );
    _searchBarSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.30),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _openAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _bodySlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _openAnimationController,
        curve: const Interval(0.10, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _bodyFadeAnimation = CurvedAnimation(
      parent: _openAnimationController,
      curve: const Interval(0.10, 1.0, curve: Curves.easeOut),
    );
    _openAnimationController.forward();
  }

  bool _focusRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Safely request focus when page transition animation completes
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
    if (!LayoutSettingsService().current.enableSearchSuggestions) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final q = _controller.text.trim();
      if (q.isEmpty) {
        setState(() {
          _query = '';
          _media.clear();
          _selectedFilter = 'all';
        });
        return;
      }
      _query = q;
      _search(q);
    });
  }

  void _performManualSearch(String text) {
    final q = text.trim();
    if (q.isEmpty) return;
    _debounce?.cancel();
    _searchFocusNode.unfocus();
    _query = q;
    _search(q);
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _loading = true);

    List<MovieBoxItem> results = await MovieBoxService.search(q);

    if (!mounted) return;
    if (_controller.text.trim() != q) return;

    setState(() {
      _media = results;
      _loading = false;
    });
  }

  Future<void> _fetchTrendingTopics() async {
    if (_trendingTopics.isEmpty) {
      setState(() => _loadingTrending = true);
    }

    try {
      final key = widget.apiKey.trim().isNotEmpty
          ? widget.apiKey
          : EnvConfig.tmdbApiKey;
      final b = widget.base.trim().isNotEmpty
          ? widget.base
          : 'https://api.themoviedb.org/3';

      if (key.isNotEmpty) {
        final url =
            Uri.parse('$b/trending/all/day?api_key=$key&language=en-US');
        final res = await http.get(url).timeout(const Duration(seconds: 12));

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final results = data['results'] as List? ?? [];
          final list = <TmdbTrendingTopic>[];
          final seen = <String>{};

          for (final r in results) {
            final title = (r['title'] ?? r['name'])?.toString().trim();
            if (title != null &&
                title.isNotEmpty &&
                !seen.contains(title.toLowerCase())) {
              seen.add(title.toLowerCase());
              final isMovie =
                  (r['media_type']?.toString().toLowerCase() != 'tv');
              list.add(TmdbTrendingTopic(title: title, isMovie: isMovie));
            }
          }

          if (list.isNotEmpty && mounted) {
            _cachedTrendingTopics = list;
            setState(() {
              _trendingTopics = list;
              _loadingTrending = false;
            });
            return;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('[Search] Error fetching TMDB trending topics: $e');
    }

    if (mounted) {
      setState(() => _loadingTrending = false);
    }
  }

  void setNavigating(bool val) {
    if (mounted) setState(() => _navigating = val);
  }

  Future<void> openDetails(MovieBoxItem item) async {
    if (_navigating) return;
    setNavigating(true);
    try {
      if (context.mounted) {
        final w = widget;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailsPage(
              apiKey: w.apiKey,
              base: w.base,
              imgW185: w.imgW185,
              imgW500: w.imgW500,
              imgW780: w.imgW780,
              id: int.tryParse(item.id) ?? 0,
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
      if (mounted) AppToast.show(context, 'Failed to open details.');
    } finally {
      setNavigating(false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    _openAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMedia;
    final hasQuery = _query.isNotEmpty;
    final hasResults = _media.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF090A0F),
      body: Stack(
        children: [
          // Ambient background glow gradients
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFB561).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 150,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF3B4A78).withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Modern Search Bar Header with entrance slide/fade animation
                SlideTransition(
                  position: _searchBarSlideAnimation,
                  child: FadeTransition(
                    opacity: _openFadeAnimation,
                    child: _ModernSearchBar(
                      controller: _controller,
                      focusNode: _searchFocusNode,
                      onSubmitted: _performManualSearch,
                      onClear: () {
                        _controller.clear();
                        setState(() {
                          _query = '';
                          _media.clear();
                          _selectedFilter = 'all';
                        });
                      },
                    ),
                  ),
                ),

                // Main Content View & Filter Bar with smooth entrance animation
                Expanded(
                  child: SlideTransition(
                    position: _bodySlideAnimation,
                    child: FadeTransition(
                      opacity: _bodyFadeAnimation,
                      child: Column(
                        children: [
                          // Live thin loading indicator
                          if (_loading)
                            Container(
                              height: 2.5,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: const LinearProgressIndicator(
                                  backgroundColor: Color(0x15FFFFFF),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFFFB561),
                                  ),
                                  minHeight: 2.5,
                                ),
                              ),
                            ),

                          // Modern Filter & View Mode Control Bar
                          if (hasQuery && (hasResults || _loading))
                            _ModernFilterBar(
                              selectedFilter: _selectedFilter,
                              totalCount: _media.length,
                              moviesCount: _moviesCount,
                              seriesCount: _seriesCount,
                              isGridView: _isGridView,
                              onFilterChanged: (filter) {
                                setState(() => _selectedFilter = filter);
                              },
                              onToggleView: (isGrid) {
                                setState(() => _isGridView = isGrid);
                              },
                            ),

                          // Main Content View
                          Expanded(
                            child: !hasQuery
                                ? _ModernDiscoveryView(
                                    showSuggestions: LayoutSettingsService()
                                        .current
                                        .enableSearchSuggestions,
                                    trendingTopics: _trendingTopics,
                                    isLoading: _loadingTrending,
                                    onSelectSuggestion: (sug) {
                                      _controller.text = sug;
                                      _controller.selection =
                                          TextSelection.fromPosition(
                                        TextPosition(offset: sug.length),
                                      );
                                      _performManualSearch(sug);
                                    },
                                  )
                                : (_loading && _media.isEmpty)
                                    ? _ModernLoadingSkeleton(
                                        isGridView: _isGridView)
                                    : (!hasResults && !_loading)
                                        ? _ModernNoResults(
                                            query: _query,
                                            onClear: () {
                                              _controller.clear();
                                              setState(() {
                                                _query = '';
                                                _media.clear();
                                                _selectedFilter = 'all';
                                              });
                                            },
                                          )
                                        : (filtered.isEmpty && !_loading)
                                            ? _ModernNoFilteredResults(
                                                selectedFilter: _selectedFilter,
                                                onResetFilter: () {
                                                  setState(() =>
                                                      _selectedFilter = 'all');
                                                },
                                              )
                                            : _ModernResults(
                                                items: filtered,
                                                isGridView: _isGridView,
                                                onItemTap: openDetails,
                                              ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Navigating Overlay
          if (_navigating)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141722).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFFFB561).withValues(alpha: 0.3),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFFFB561),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Opening title...',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
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

// ==========================================
// 1. MODERN SEARCH BAR
// ==========================================

class _ModernSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onClear;

  const _ModernSearchBar({
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // Sleek liquid glass back button
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.09),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white70,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Search Input Capsule with Liquid Glass & Centered Field
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.055),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                      width: 1,
                    ),
                  ),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        textAlignVertical: TextAlignVertical.center,
                        textInputAction: TextInputAction.search,
                        onSubmitted: onSubmitted,
                        cursorColor: const Color(0xFFFFB561),
                        cursorHeight: 20,
                        cursorWidth: 2,
                        cursorRadius: const Radius.circular(2),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.only(right: 14),
                          hintText: 'Search movies, web series, anime...',
                          hintStyle: GoogleFonts.outfit(
                            color: Colors.white.withValues(alpha: 0.32),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w400,
                            letterSpacing: -0.2,
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 14, right: 10),
                            child: Hero(
                              tag: 'search-icon',
                              child: Material(
                                type: MaterialType.transparency,
                                child: HugeIcon(
                                  icon: HugeIcons.strokeRoundedSearch01,
                                  color: value.text.isNotEmpty
                                      ? const Color(0xFFFFB561)
                                      : Colors.white.withValues(alpha: 0.50),
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 45,
                            minHeight: 52,
                          ),
                          suffixIcon: value.text.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 42,
                                    minHeight: 52,
                                  ),
                                  icon: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white70,
                                      size: 15,
                                    ),
                                  ),
                                  onPressed: onClear,
                                  splashRadius: 20,
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 42,
                            minHeight: 52,
                          ),
                        ),
                      );
                    },
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

// ==========================================
// 2. MODERN FILTER & VIEW MODE BAR
// ==========================================

class _ModernFilterBar extends StatelessWidget {
  final String selectedFilter;
  final int totalCount;
  final int moviesCount;
  final int seriesCount;
  final bool isGridView;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<bool> onToggleView;

  const _ModernFilterBar({
    required this.selectedFilter,
    required this.totalCount,
    required this.moviesCount,
    required this.seriesCount,
    required this.isGridView,
    required this.onFilterChanged,
    required this.onToggleView,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          // Filter Tabs (All, Movies, Series)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    count: totalCount,
                    isSelected: selectedFilter == 'all',
                    onTap: () => onFilterChanged('all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Movies',
                    count: moviesCount,
                    icon: Icons.movie_filter_rounded,
                    isSelected: selectedFilter == 'movie',
                    onTap: () => onFilterChanged('movie'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Series',
                    count: seriesCount,
                    icon: Icons.tv_rounded,
                    isSelected: selectedFilter == 'series',
                    onTap: () => onFilterChanged('series'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // View Switcher (Grid vs List)
          Container(
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewToggleButton(
                  icon: Icons.grid_view_rounded,
                  tooltip: 'Poster Grid',
                  isActive: isGridView,
                  onTap: () => onToggleView(true),
                ),
                const SizedBox(width: 3),
                _ViewToggleButton(
                  icon: Icons.view_agenda_rounded,
                  tooltip: 'Detailed List',
                  isActive: !isGridView,
                  onTap: () => onToggleView(false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFB561)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFB561)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFB561).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? const Color(0xFF0C0D12)
                    : Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected
                    ? const Color(0xFF0C0D12)
                    : Colors.white.withValues(alpha: 0.75),
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.black.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.outfit(
                  color: isSelected
                      ? const Color(0xFF0C0D12)
                      : Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _ViewToggleButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFFFB561)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? const Color(0xFF0C0D12) : Colors.white54,
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 3. MODERN RESULTS VIEW (GRID & LIST)
// ==========================================

class _ModernResults extends StatelessWidget {
  final List<MovieBoxItem> items;
  final bool isGridView;
  final void Function(MovieBoxItem) onItemTap;

  const _ModernResults({
    required this.items,
    required this.isGridView,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Responsive columns
    final cols = width < 440
        ? 3
        : (width < 700 ? 4 : (width < 1050 ? 5 : (width < 1400 ? 6 : 7)));

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Results count badge row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFB561),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${items.length} titles available',
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (isGridView)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 18,
                crossAxisSpacing: 12,
                childAspectRatio: 0.60,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = items[i];
                  return _ModernGridCard(
                    item: item,
                    onTap: () => onItemTap(item),
                  );
                },
                childCount: items.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = items[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ModernListCard(
                      item: item,
                      onTap: () => onItemTap(item),
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ==========================================
// 4. MODERN GRID CARD
// ==========================================

class _ModernGridCard extends StatefulWidget {
  final MovieBoxItem item;
  final VoidCallback onTap;

  const _ModernGridCard({
    required this.item,
    required this.onTap,
  });

  @override
  State<_ModernGridCard> createState() => _ModernGridCardState();
}

class _ModernGridCardState extends State<_ModernGridCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final yearStr = item.yearLabel;
    final hasYear = yearStr.isNotEmpty;
    final titleText = item.displayTitle;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.04 : 1.0),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster Frame
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isHovered
                          ? const Color(0xFFFFB561)
                          : Colors.white.withValues(alpha: 0.08),
                      width: _isHovered ? 1.4 : 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: _isHovered ? 0.65 : 0.40),
                        blurRadius: _isHovered ? 16 : 8,
                        offset: const Offset(0, 4),
                      ),
                      if (_isHovered)
                        BoxShadow(
                          color: const Color(0xFFFFB561).withValues(alpha: 0.28),
                          blurRadius: 16,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Poster Image
                        if (item.poster != null && item.poster!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: item.poster!,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 200),
                            placeholder: (context, url) => Container(
                              color: const Color(0xFF141722),
                              child: const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFFFFB561),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF141722),
                              child: const Icon(
                                Icons.movie_outlined,
                                color: Colors.white24,
                                size: 28,
                              ),
                            ),
                          )
                        else
                          Container(
                            color: const Color(0xFF141722),
                            child: const Icon(
                              Icons.movie_outlined,
                              color: Colors.white24,
                              size: 28,
                            ),
                          ),

                        // Vignette Shadow Gradient
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.0, 0.45, 1.0],
                              colors: [
                                Colors.black.withValues(alpha: 0.35),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                        ),

                        // Media Type Badge (Top Left)
                        Positioned(
                          top: 7,
                          left: 7,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: item.isMovie
                                      ? const Color(0xFFFFB561).withValues(alpha: 0.22)
                                      : const Color(0xFF5E9EFF).withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: item.isMovie
                                        ? const Color(0xFFFFB561).withValues(alpha: 0.5)
                                        : const Color(0xFF5E9EFF).withValues(alpha: 0.5),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  item.isMovie ? 'MOVIE' : 'SERIES',
                                  style: GoogleFonts.outfit(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: item.isMovie
                                        ? const Color(0xFFFFB561)
                                        : const Color(0xFF90BFFF),
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Year Badge (Top Right)
                        if (hasYear)
                          Positioned(
                            top: 7,
                            right: 7,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.60),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.12),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        size: 9.5,
                                        color: const Color(0xFFFFB561).withValues(alpha: 0.9),
                                      ),
                                      const SizedBox(width: 3.5),
                                      Text(
                                        yearStr,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Hover Play Overlay
                        if (_isHovered)
                          Center(
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB561).withValues(alpha: 0.92),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFFB561).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Color(0xFF0C0D12),
                                size: 24,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Title beneath poster
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  titleText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: _isHovered
                        ? const Color(0xFFFFB561)
                        : Colors.white.withValues(alpha: 0.90),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 5. MODERN DETAILED LIST CARD
// ==========================================

class _ModernListCard extends StatefulWidget {
  final MovieBoxItem item;
  final VoidCallback onTap;

  const _ModernListCard({
    required this.item,
    required this.onTap,
  });

  @override
  State<_ModernListCard> createState() => _ModernListCardState();
}

class _ModernListCardState extends State<_ModernListCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final yearStr = item.yearLabel;
    final hasYear = yearStr.isNotEmpty;
    final titleText = item.displayTitle;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : (_isHovered ? 1.01 : 1.0),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isHovered
                    ? const Color(0xFFFFB561).withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isHovered ? 0.45 : 0.25),
                  blurRadius: _isHovered ? 14 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // 2:3 Aspect ratio poster thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 65,
                    height: 95,
                    child: item.poster != null && item.poster!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.poster!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: const Color(0xFF141722),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF141722),
                              child: const Icon(
                                Icons.movie_outlined,
                                color: Colors.white24,
                              ),
                            ),
                          )
                        : Container(
                            color: const Color(0xFF141722),
                            child: const Icon(
                              Icons.movie_outlined,
                              color: Colors.white24,
                            ),
                          ),
                  ),
                ),

                const SizedBox(width: 14),

                // Title and Meta Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Badge Row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: item.isMovie
                                  ? const Color(0xFFFFB561).withValues(alpha: 0.18)
                                  : const Color(0xFF5E9EFF).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: item.isMovie
                                    ? const Color(0xFFFFB561).withValues(alpha: 0.45)
                                    : const Color(0xFF5E9EFF).withValues(alpha: 0.45),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              item.isMovie ? 'MOVIE' : 'SERIES',
                              style: GoogleFonts.outfit(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: item.isMovie
                                    ? const Color(0xFFFFB561)
                                    : const Color(0xFF90BFFF),
                              ),
                            ),
                          ),
                          if (hasYear) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 10,
                                    color: const Color(0xFFFFB561).withValues(alpha: 0.9),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    yearStr,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Title
                      Text(
                        titleText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: _isHovered
                              ? const Color(0xFFFFB561)
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),

                      const SizedBox(height: 5),

                      // Subtitle
                      Text(
                        'Tap to stream & view sources',
                        style: GoogleFonts.outfit(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Right Action Button
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _isHovered
                        ? const Color(0xFFFFB561)
                        : Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isHovered
                          ? const Color(0xFFFFB561)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: _isHovered
                        ? const Color(0xFF0C0D12)
                        : Colors.white70,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 6. MODERN LOADING SKELETON
// ==========================================

class _ModernLoadingSkeleton extends StatefulWidget {
  final bool isGridView;

  const _ModernLoadingSkeleton({required this.isGridView});

  @override
  State<_ModernLoadingSkeleton> createState() => _ModernLoadingSkeletonState();
}

class _ModernLoadingSkeletonState extends State<_ModernLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.04, end: 0.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width < 440
        ? 3
        : (width < 700 ? 4 : (width < 1050 ? 5 : 6));

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final shimmerColor = Colors.white.withValues(alpha: _animation.value);

        if (widget.isGridView) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 18,
              crossAxisSpacing: 12,
              childAspectRatio: 0.60,
            ),
            itemCount: cols * 2,
            itemBuilder: (context, i) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: shimmerColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    height: 12,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 50,
                    height: 10,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              );
            },
          );
        } else {
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 6,
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  height: 110,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 65,
                        height: 90,
                        decoration: BoxDecoration(
                          color: shimmerColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 60,
                              height: 14,
                              decoration: BoxDecoration(
                                color: shimmerColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 180,
                              height: 16,
                              decoration: BoxDecoration(
                                color: shimmerColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 120,
                              height: 12,
                              decoration: BoxDecoration(
                                color: shimmerColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      },
    );
  }
}

// ==========================================
// 7. MODERN DISCOVERY & EMPTY STATE
// ==========================================

class TmdbTrendingTopic {
  final String title;
  final bool isMovie;

  const TmdbTrendingTopic({
    required this.title,
    required this.isMovie,
  });
}

class _ModernDiscoveryView extends StatelessWidget {
  final bool showSuggestions;
  final List<TmdbTrendingTopic> trendingTopics;
  final bool isLoading;
  final ValueChanged<String>? onSelectSuggestion;

  const _ModernDiscoveryView({
    required this.showSuggestions,
    required this.trendingTopics,
    required this.isLoading,
    this.onSelectSuggestion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Center Glowing Icon Card
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFB561).withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB561).withValues(alpha: 0.12),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 34,
                color: Color(0xFFFFB561),
              ),
            ),
            const SizedBox(height: 18),

            Text(
              'Discover Movies & Series',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Search across high speed streaming sources',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
            ),

            if (showSuggestions) ...[
              const SizedBox(height: 36),

              // Trending header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    size: 16,
                    color: Color(0xFFFFB561),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'TRENDING TOPIC',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.50),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (isLoading && trendingTopics.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFFFB561),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Loading trending titles...',
                        style: GoogleFonts.outfit(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else if (trendingTopics.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 9,
                  alignment: WrapAlignment.center,
                  children: trendingTopics.take(18).map((topic) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => onSelectSuggestion?.call(topic.title),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.09),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                topic.isMovie
                                    ? Icons.movie_filter_rounded
                                    : Icons.tv_rounded,
                                size: 14,
                                color: const Color(0xFFFFB561)
                                    .withValues(alpha: 0.85),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                topic.title,
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 8. MODERN NO RESULTS FOUND
// ==========================================

class _ModernNoResults extends StatelessWidget {
  final String query;
  final VoidCallback onClear;

  const _ModernNoResults({
    required this.query,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  size: 32,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No titles found',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We couldn\'t find any match for "$query". Check for spelling errors or try broader keywords.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB561).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFFB561).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'Clear Search',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFFFFB561),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 9. NO FILTERED RESULTS (E.G. NO TV SHOWS IN MOVIES SEARCH)
// ==========================================

class _ModernNoFilteredResults extends StatelessWidget {
  final String selectedFilter;
  final VoidCallback onResetFilter;

  const _ModernNoFilteredResults({
    required this.selectedFilter,
    required this.onResetFilter,
  });

  @override
  Widget build(BuildContext context) {
    final typeName = selectedFilter == 'movie' ? 'movies' : 'series';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selectedFilter == 'movie'
                  ? Icons.movie_filter_rounded
                  : Icons.tv_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 14),
            Text(
              'No $typeName in results',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try switching your filter to "All" to view other matching categories.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: onResetFilter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB561),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Show All Results',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF0C0D12),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
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
