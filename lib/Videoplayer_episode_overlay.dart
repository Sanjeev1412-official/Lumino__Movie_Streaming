// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// TODO: replace these with your real imports
// import 'package:your_app/models/tv_season_meta.dart';
// import 'package:your_app/models/tv_episode_summary.dart';
// import 'package:your_app/widgets/three_d_button_3d.dart';

/// Adjust these to your actual types.
class TvSeasonMeta {
  final int seasonNumber;
  final int? episodeCount; // NEW
  TvSeasonMeta({required this.seasonNumber, this.episodeCount});
}

class TvEpisodeSummary {
  final int season;
  final int episode;
  final String title;
  final String? overview;
  final String? stillPath;
  final int? runtime;

  TvEpisodeSummary({
    required this.season,
    required this.episode,
    required this.title,
    this.overview,
    this.stillPath,
    this.runtime,
  });
}

/// Extracted overlay widget. All state + logic is still controlled
/// by the parent via the provided parameters and callbacks.
class EpisodeOverlay extends StatelessWidget {
  const EpisodeOverlay({
    super.key,
    required this.seasons,
    required this.title,
    required this.episodeCache,
    required this.hasOverlay,
    required this.isLoading,
    this.error,
    this.selectedSeason,
    this.initialSeason,
    this.initialEpisode,
    this.onEpisodeSelected,
    this.onClose,
    this.onSeasonTap,
    required this.isDesktop,
  });

  /// Same as `widget.seasonsMeta ?? []`
  final List<TvSeasonMeta> seasons;

  /// Same as `widget.title`
  final String title;

  /// Same as `_episodeCache`
  final Map<int, List<TvEpisodeSummary>> episodeCache;

  /// Same as `_hasEpisodeOverlay`
  final bool hasOverlay;

  /// Same as `_episodeOverlayLoading`
  final bool isLoading;

  /// Same as `_episodeOverlayError`
  final String? error;

  /// Same as `_episodeOverlaySeason`
  final int? selectedSeason;

  /// Same as `widget.initialSeason`
  final int? initialSeason;

  /// Same as `widget.initialEpisode`
  final int? initialEpisode;

  /// Same as `widget.onEpisodeSelected`
  final void Function(int season, int episode, String title)? onEpisodeSelected;

  /// Replaces:
  ///   setState(() => _showEpisodeOverlay = false);
  ///   await _player.play();
  final Future<void> Function()? onClose;

  /// Replaces the season chip onTap:
  ///
  ///   setState(() => _episodeOverlaySeason = s.seasonNumber);
  ///   if (!_episodeCache.containsKey(s.seasonNumber)) {
  ///     _loadSeasonEpisodes(s.seasonNumber);
  ///   }
  final void Function(int seasonNumber)? onSeasonTap;

  /// Same as `_isDesktop`
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty || !hasOverlay) {
      return const SizedBox.shrink();
    }

    final effectiveSelectedSeason = selectedSeason ?? seasons.first.seasonNumber;
    final episodes = episodeCache[effectiveSelectedSeason] ?? const <TvEpisodeSummary>[];

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF050509).withValues(alpha: 0.94),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ----- Header -----
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB561).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.playlist_play_rounded, size: 24, color: Color(0xFFFFB561)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UP NEXT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFB561),
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, size: 24, color: Colors.white70),
                      ),
                      onPressed: () async {
                        if (onClose != null) await onClose!();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              
              // ----- Seasons Selector (Sync with DetailsPage) -----
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: seasons.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final s = seasons[index];
                    final isSelected = s.seasonNumber == effectiveSelectedSeason;
                    final epCount = s.episodeCount != null ? ' (${s.episodeCount})' : '';
                    
                    return InkWell(
                      onTap: () {
                        if (!isSelected && onSeasonTap != null) {
                          onSeasonTap!(s.seasonNumber);
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [Color(0xFFFFE3B5), Color(0xFFFFB561)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected ? null : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          'Season ${s.seasonNumber}$epCount',
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // ----- Episodes List (Sync with DetailsPage style) -----
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (isLoading && episodes.isEmpty) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB561)));
                    }

                    if (error != null && episodes.isEmpty) {
                      return Center(child: Text(error!, style: const TextStyle(color: Colors.white70)));
                    }

                    if (episodes.isEmpty) {
                      return const Center(child: Text('No episodes found.', style: TextStyle(color: Colors.white70)));
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      itemCount: episodes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final e = episodes[index];
                        final isCurrent = (initialSeason == e.season && initialEpisode == e.episode);

                        return InkWell(
                          onTap: () {
                            if (onEpisodeSelected != null) {
                              onEpisodeSelected!(e.season, e.episode, e.title);
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isCurrent 
                                  ? Colors.white.withValues(alpha: 0.12) 
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isCurrent 
                                    ? const Color(0xFFFFB561).withValues(alpha: 0.4) 
                                    : Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thumbnail (Sync with DetailsPage)
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: SizedBox(
                                        width: 140,
                                        height: 80,
                                        child: e.stillPath != null
                                            ? CachedNetworkImage(
                                                imageUrl: 'https://image.tmdb.org/t/p/w300${e.stillPath}',
                                                fit: BoxFit.cover,
                                              )
                                            : Container(color: Colors.white10),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.black45,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white30),
                                          ),
                                          child: Icon(
                                            isCurrent ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                            color: isCurrent ? const Color(0xFFFFB561) : Colors.white,
                                            size: 26,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                // Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'EPISODE ${e.episode}',
                                            style: const TextStyle(
                                              color: Color(0xFFFFB561),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                          if (e.runtime != null && e.runtime! > 0) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              '• ${e.runtime}m',
                                              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        e.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                        ),
                                      ),
                                      if (e.overview != null && e.overview!.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          e.overview!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white.withValues(alpha: 0.6),
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dummy to make this file self-contained. Remove when you import your real one.
enum ThreeDButtonShape { pill, circle }

class ThreeDButton3D extends StatelessWidget {
  const ThreeDButton3D({
    super.key,
    required this.shape,
    this.label,
    this.icon,
    this.height,
    this.isSelected = false,
    this.onTap,
  });

  final ThreeDButtonShape shape;
  final String? label;
  final Widget? icon;
  final double? height;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Replace with your real implementation.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height ?? 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: isSelected ? Colors.orange : Colors.grey[800],
        ),
        child: icon ??
            Text(
              label ?? '',
              style: const TextStyle(color: Colors.white),
            ),
      ),
    );
  }
}
