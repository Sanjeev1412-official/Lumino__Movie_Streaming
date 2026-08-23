import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lumino_app_moviestreaming/livetv_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:lumino_app_moviestreaming/videoplayer.dart';
import 'package:lumino_app_moviestreaming/toast.dart';

class LiveTvPage extends StatefulWidget {
  const LiveTvPage({super.key});

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends State<LiveTvPage> with SingleTickerProviderStateMixin {
  final LiveTvService _liveTvService = LiveTvService();
  late Future<List<LiveTvChannel>> _channelsFuture;
  late Future<List<LiveTvEvent>> _eventsFuture;
  List<LiveTvChannel> _allChannels = [];
  List<LiveTvChannel> _filteredChannels = [];
  List<LiveTvEvent> _allEvents = [];
  List<LiveTvEvent> _filteredEvents = [];
  
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  late TabController _tabController;
  Timer? _timeTimer;
  Timer? _refreshTimer;
  String _currentTime = '';
  String _selectedEventStatus = 'All';
  String _selectedEventCategory = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _updateTime();
    _timeTimer = Timer.periodic(const Duration(minutes: 1), (timer) => _updateTime());
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) => _loadData());
    _loadData();
  }

  void _updateTime() {
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('hh:mm a').format(DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timeTimer?.cancel();
    _refreshTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    _eventsFuture = _liveTvService.fetchEvents().then((events) {
      if (mounted) {
        setState(() {
          _allEvents = events;
          if (_searchController.text.isEmpty) {
            _filteredEvents = events;
          } else {
            final query = _searchController.text.toLowerCase();
            _filteredEvents = events
                .where((event) =>
                    event.event.toLowerCase().contains(query) ||
                    event.tournament.toLowerCase().contains(query))
                .toList();
          }
        });
      }
      return events;
    });

    _channelsFuture = _liveTvService.fetchChannels().then((channels) {
      if (mounted) {
        setState(() {
          _allChannels = channels;
          if (_searchController.text.isEmpty) {
            _filteredChannels = channels;
          } else {
            final query = _searchController.text.toLowerCase();
            _filteredChannels = channels
                .where((channel) =>
                    channel.name.toLowerCase().contains(query))
                .toList();
          }
        });
      }
      return channels;
    });
  }

  void _filterData(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredChannels = _allChannels;
        _filteredEvents = _allEvents;
      } else {
        _filteredChannels = _allChannels
            .where((channel) =>
                channel.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
        _filteredEvents = _allEvents
            .where((event) =>
                event.event.toLowerCase().contains(query.toLowerCase()) ||
                event.tournament.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: Stack(
        children: [
          // Background Glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFB561).withValues(alpha: 0.05),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                _buildTabs(),
                _buildSearchBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEventsSection(),
                      _buildChannelsSection(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 380;

    return Padding(
      padding: EdgeInsets.fromLTRB(isSmallScreen ? 16 : 24, 16, isSmallScreen ? 16 : 24, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: isSmallScreen ? 18 : 20),
            ),
          ),
          SizedBox(width: isSmallScreen ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIVE TV',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFFFB561),
                    fontSize: isSmallScreen ? 14 : 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: isSmallScreen ? 1 : 2,
                  ),
                ),
                if (!isSmallScreen)
                  Text(
                    'Experience TV in real-time',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _currentTime,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 14 : 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: isSmallScreen ? 8 : 16),
              _buildLiveIndicator(isSmallScreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveIndicator(bool isSmall) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00FF00).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00FF00).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isSmall ? 6 : 8,
            height: isSmall ? 6 : 8,
            decoration: const BoxDecoration(
              color: Color(0xFF00FF00),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: isSmall ? 4 : 6),
          Text(
            'LIVE',
            style: GoogleFonts.outfit(
              color: const Color(0xFF00FF00),
              fontSize: isSmall ? 5 : 6,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildTabs() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 380;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16 : 24, vertical: 12),
      child: Container(
        height: isSmallScreen ? 48 : 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: const Color(0xFFFFB561),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB561).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          labelColor: Colors.black,
          unselectedLabelColor: Colors.white54,
          labelStyle: GoogleFonts.outfit(
            fontSize: isSmallScreen ? 13 : 14,
            fontWeight: FontWeight.w800,
            letterSpacing: isSmallScreen ? 0 : 0.5,
          ),
          unselectedLabelStyle: GoogleFonts.outfit(
            fontSize: isSmallScreen ? 13 : 14,
            fontWeight: FontWeight.w600,
          ),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sports_score_rounded, size: isSmallScreen ? 16 : 18),
                  SizedBox(width: isSmallScreen ? 4 : 8),
                  const Text('Live Matches'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tv_rounded, size: isSmallScreen ? 16 : 18),
                  SizedBox(width: isSmallScreen ? 4 : 8),
                  const Text('All Channels'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isSearching ? const Color(0xFFFFB561).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _filterData,
          onTap: () => setState(() => _isSearching = true),
          onSubmitted: (_) => setState(() => _isSearching = false),
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search...',
            hintStyle: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.search_rounded, color: Colors.white54),
            suffixIcon: _searchController.text.isNotEmpty 
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () {
                    _searchController.clear();
                    _filterData('');
                  },
                )
              : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildEventsSection() {
    return FutureBuilder<List<LiveTvEvent>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _allEvents.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB561)));
        } else if (snapshot.hasError && _allEvents.isEmpty) {
          return _buildErrorState('events');
        } else if (_allEvents.isEmpty) {
          return _buildEmptyState('events');
        }

        final filteredByStatus = _selectedEventStatus == 'All'
            ? _filteredEvents
            : _filteredEvents.where((e) {
                if (_selectedEventStatus == 'Live') return e.isLive;
                if (_selectedEventStatus == 'Upcoming') return e.isUpcoming;
                if (_selectedEventStatus == 'Finished') return e.isFinished;
                return e.status.toLowerCase() == _selectedEventStatus.toLowerCase();
              }).toList();

        final filteredByStatusAndCategory = _selectedEventCategory == 'All'
            ? filteredByStatus
            : filteredByStatus.where((e) => e.category.toLowerCase() == _selectedEventCategory.toLowerCase()).toList();

        if (filteredByStatusAndCategory.isEmpty && _allEvents.isNotEmpty) {
          return Column(
            children: [
              _buildEventStatusFilters(),
              _buildEventCategoryFilters(),
              Expanded(child: _buildNoResultsState()),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          physics: const BouncingScrollPhysics(),
          children: [
            _buildEventStatusFilters(),
            _buildEventCategoryFilters(),
            ...filteredByStatusAndCategory.map((event) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildEventCard(event),
            )),
          ],
        );
      },
    );
  }

  Widget _buildEventCategoryFilters() {
    // Extract unique categories from all events
    final List<String> categories = ['All'];
    for (var event in _allEvents) {
      if (event.category.isNotEmpty && !categories.contains(event.category)) {
        categories.add(event.category);
      }
    }

    if (categories.length <= 1) return const SizedBox.shrink();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Row(
          children: categories.map((category) {
            bool isSelected = _selectedEventCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilterChip(
                label: Text(
                  category,
                  style: GoogleFonts.outfit(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedEventCategory = category;
                  });
                },
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                selectedColor: const Color(0xFFFFB561).withValues(alpha: 0.8),
                checkmarkColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.1)),
                ),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEventStatusFilters() {
    final statuses = ['All', 'Live', 'Upcoming', 'Finished'];
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Row(
          children: statuses.map((status) {
            bool isSelected = _selectedEventStatus == status;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilterChip(
                label: Text(
                  status,
                  style: GoogleFonts.outfit(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedEventStatus = status;
                  });
                },
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                selectedColor: const Color(0xFFFFB561),
                checkmarkColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.1)),
                ),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEventCard(LiveTvEvent event) {
    Color statusColor = event.isLive ? const Color(0xFF00FF00) : (event.isUpcoming ? Colors.blue : Colors.grey);
    bool isTeamEvent = event.homeTeam != null && event.awayTeam != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showChannelSelection(event),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left Section: Sport Category Badge
                Container(
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getSportIcon(event.category),
                          color: const Color(0xFFFFB561),
                          size: 24,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          event.category.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 6,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                
                // Middle Section: Event Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tournament Name
                      Text(
                        event.tournament,
                        style: GoogleFonts.outfit(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      
                      if (isTeamEvent)
                        // Team vs Team Layout (Left Aligned)
                        Row(
                          children: [
                            _buildTeamLogo(event.homeTeamIMG),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${event.homeTeam!} vs ${event.awayTeam!}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildTeamLogo(event.awayTeamIMG),
                          ],
                        )
                      else
                        // Standard Event Layout
                        Text(
                          event.event,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        
                      const SizedBox(height: 8),
                      // Time and Status
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              event.displayStatus,
                              style: GoogleFonts.outfit(
                                color: statusColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.access_time_rounded, size: 12, color: Colors.white.withValues(alpha: 0.3)),
                          const SizedBox(width: 4),
                          Text(
                            _formatEventTimeRange(event.start, event.end),
                            style: GoogleFonts.outfit(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildTeamLogo(String? url) {
    return Container(
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        shape: BoxShape.circle,
      ),
      child: _buildNetworkImage(
        url,
        placeholder: const Icon(Icons.shield_rounded, color: Colors.white10, size: 16),
        fit: BoxFit.contain,
      ),
    );
  }

  void _showChannelSelection(LiveTvEvent event) {
    if (event.channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No channels available for this event yet.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Channel',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                event.event,
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: event.channels.length,
                  itemBuilder: (context, index) {
                    final channel = event.channels[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                        onTap: () {
                          Navigator.pop(context);
                          if (channel.code != null && channel.code!.trim().isNotEmpty) {
                            _handlePlayback(channel.name, channel.code!);
                          } else if (channel.url.isNotEmpty) {
                            _playChannel(channel);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No stream available for this channel')));
                          }
                        },
                        leading: Container(
                          width: 40,
                          height: 40,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: _buildNetworkImage(
                            channel.image,
                            placeholder: const Icon(Icons.tv, color: Colors.white24, size: 20),
                            fit: BoxFit.contain,
                          ),
                        ),
                        title: Text(
                          channel.name,
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        trailing: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFFFB561)),
                      ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelsSection() {
    return FutureBuilder<List<LiveTvChannel>>(
      future: _channelsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _allChannels.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB561)));
        } else if (snapshot.hasError && _allChannels.isEmpty) {
          return _buildErrorState('channels');
        } else if (_filteredChannels.isEmpty && _allChannels.isNotEmpty) {
          return _buildNoResultsState();
        } else if (_allChannels.isEmpty) {
          return _buildEmptyState('channels');
        }

        return _buildChannelGrid();
      },
    );
  }

  Widget _buildChannelGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Dynamically adjust columns based on available width for a responsive, modern grid
        int crossAxisCount = constraints.maxWidth > 1200 ? 6 : constraints.maxWidth > 900 ? 5 : constraints.maxWidth > 600 ? 4 : constraints.maxWidth > 400 ? 3 : 2;
        
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.82, // Slightly taller to accommodate the new bottom info bar
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: _filteredChannels.length,
          itemBuilder: (context, index) {
            final channel = _filteredChannels[index];
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 400 + (index % 10) * 50),
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
              child: _buildChannelCard(channel),
            );
          },
        );
      },
    );
  }

  Widget _buildChannelCard(LiveTvChannel channel) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161D).withValues(alpha: 0.8), // Rich dark background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (channel.code != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChannelDetailsPage(channel: channel),
                  ),
                );
              } else {
                _playChannel(channel);
              }
            },
            splashColor: const Color(0xFFFFB561).withValues(alpha: 0.2),
            highlightColor: const Color(0xFFFFB561).withValues(alpha: 0.1),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Inner gradient background for the logo area
                Positioned(
                  top: 0, left: 0, right: 0, bottom: 44,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.03),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: _buildNetworkImage(
                      channel.image,
                      placeholder: const Icon(Icons.tv_rounded, color: Colors.white10, size: 40),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                // Play button overlay (subtle)
                Positioned(
                  top: 0, left: 0, right: 0, bottom: 44,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 24),
                    ),
                  ),
                ),
                // Bottom Info Bar
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C0D12),
                      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: channel.isOnline ? const Color(0xFF00FF00) : Colors.redAccent,
                                shape: BoxShape.circle,
                                boxShadow: channel.isOnline ? [
                                  BoxShadow(
                                    color: const Color(0xFF00FF00).withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  )
                                ] : null,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                channel.status.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Icon(Icons.remove_red_eye_rounded, size: 10, color: Colors.white.withValues(alpha: 0.4)),
                            const SizedBox(width: 2),
                            Text(
                              '${channel.viewers}',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  void _playChannel(LiveTvChannel channel) async {
    if (channel.code != null) {
      _handlePlayback(channel.name, channel.code!);
      return;
    }
    
    final Uri url = Uri.parse(channel.url);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handlePlayback(String name, String code) async {
    // Show loading state
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFB561)),
      ),
    );

    try {
      final streamData = await _liveTvService.fetchStreamData(name, code);
      if (mounted) Navigator.pop(context); // Close loader

      if (streamData == null) {
        if (mounted) AppToast.show(context, 'Failed to fetch stream', icon: Icons.error_rounded);
        return;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(
              title: name,
              episodeTitle: 'Live TV',
              mediaUrl: streamData.url,
              httpMetadata: {
                'direct': {
                  'headers': streamData.headers,
                }
              },
              isLiveTv: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppToast.show(context, 'Error: $e', icon: Icons.error_rounded);
      }
    }
  }

  Widget _buildErrorState(String type) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 64),
          const SizedBox(height: 16),
          Text(
            'Failed to load $type',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _loadData,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB561)),
            child: Text('Retry', style: GoogleFonts.outfit(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, color: Colors.white.withValues(alpha: 0.2), size: 64),
          const SizedBox(height: 16),
          Text(
            'No results found matching "${_searchController.text}"',
            style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String type) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tv_off_rounded, color: Colors.white.withValues(alpha: 0.2), size: 64),
          const SizedBox(height: 16),
          Text(
            'No $type available right now',
            style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkImage(String? url, {Widget? placeholder, BoxFit fit = BoxFit.cover}) {
    if (url == null || url.isEmpty) {
      return placeholder ?? const Icon(Icons.image_not_supported_rounded, color: Colors.white24);
    }

    if (url.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        url,
        fit: fit,
        placeholderBuilder: (context) => placeholder ?? const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (context, url) => placeholder ?? const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorWidget: (context, url, error) => placeholder ?? const Icon(Icons.error_outline, color: Colors.white24),
    );
  }

  IconData _getSportIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('football') || cat.contains('soccer') || cat.contains('futsal')) {
      return Icons.sports_soccer_rounded;
    } else if (cat.contains('basketball')) {
      return Icons.sports_basketball_rounded;
    } else if (cat.contains('cricket')) {
      return Icons.sports_cricket_rounded;
    } else if (cat.contains('tennis')) {
      return Icons.sports_tennis_rounded;
    } else if (cat.contains('motorsport')) {
      return Icons.sports_motorsports_rounded;
    } else if (cat.contains('mma') || cat.contains('boxing') || cat.contains('wrestling')) {
      return Icons.sports_kabaddi_rounded; // MMA/Wrestling
    } else if (cat.contains('golf')) {
      return Icons.sports_golf_rounded;
    } else if (cat.contains('hockey')) {
      return Icons.sports_hockey_rounded;
    } else if (cat.contains('cycling')) {
      return Icons.directions_bike_rounded;
    } else if (cat.contains('baseball') || cat.contains('mlb')) {
      return Icons.sports_baseball_rounded;
    } else if (cat.contains('badminton')) {
      return Icons.sports_handball_rounded; // Closest material icon
    } else if (cat.contains('handball')) {
      return Icons.sports_handball_rounded;
    } else if (cat.contains('horse')) {
      return Icons.bedroom_baby_rounded; // Fallback for horse racing
    }
    return Icons.emoji_events_rounded;
  }

  String _formatEventTimeRange(String start, String end) {
    try {
      // API times are in UTC (e.g., "2026-05-15 14:00"), so we add 'Z' to parse as UTC
      // then convert to local time for the user.
      DateTime startTime = DateTime.parse('${start.replaceAll(' ', 'T')}Z').toLocal();
      DateTime endTime = DateTime.parse('${end.replaceAll(' ', 'T')}Z').toLocal();
      
      String formattedStart = DateFormat('hh:mm a').format(startTime);
      String formattedEnd = DateFormat('hh:mm a').format(endTime);
      
      return '$formattedStart - $formattedEnd';
    } catch (e) {
      return '$start - $end';
    }
  }
}

class ChannelDetailsPage extends StatefulWidget {
  final LiveTvChannel channel;
  const ChannelDetailsPage({super.key, required this.channel});
  @override
  State<ChannelDetailsPage> createState() => _ChannelDetailsPageState();
}

class _ChannelDetailsPageState extends State<ChannelDetailsPage> {
  final LiveTvService _service = LiveTvService();
  late Future<ChannelDetails?> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _service.fetchChannelDetails(widget.channel.name, widget.channel.code ?? '');
  }

  Future<void> _playChannelFromUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch player')));
    }
  }

  Widget _buildNetworkImage(String? url, {BoxFit fit = BoxFit.cover, Widget? placeholder}) {
    if (url == null || url.isEmpty) return placeholder ?? const Icon(Icons.tv, color: Colors.white24, size: 30);
    if (url.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(url, fit: fit, placeholderBuilder: (_) => placeholder ?? const SizedBox());
    }
    return CachedNetworkImage(
      imageUrl: url, fit: fit,
      placeholder: (_, _) => placeholder ?? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFB561))),
      errorWidget: (_, _, _) => placeholder ?? const Icon(Icons.error_outline, color: Colors.white24),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: FutureBuilder<ChannelDetails?>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB561)));
          }
          final details = snapshot.data;
          if (details == null) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.signal_wifi_off_rounded, size: 64, color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(height: 16),
                Text('No data available', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => setState(() => _detailsFuture = _service.fetchChannelDetails(widget.channel.name, widget.channel.code ?? '')),
                  child: const Text('Retry', style: TextStyle(color: Color(0xFFFFB561))),
                ),
              ]),
            );
          }
          return _buildBody(details);
        },
      ),
    );
  }

  Widget _buildBody(ChannelDetails details) {
    return Stack(
      children: [
        // --- Ambient blurred background ---
        Positioned.fill(
          child: Stack(children: [
            _buildNetworkImage(details.logoUrl, fit: BoxFit.cover),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(color: const Color(0xFF0A0A0F).withValues(alpha: 0.92)),
            ),
          ]),
        ),

        // --- Scrollable content ---
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Back button bar
            SliverToBoxAdapter(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Hero Header â€” logo, name, watch button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Column(
                  children: [
                    // Logo
                    Container(
                      width: 120, height: 120,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFFFB561).withValues(alpha: 0.15), blurRadius: 50, spreadRadius: 5),
                        ],
                      ),
                      child: _buildNetworkImage(details.logoUrl, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      details.name,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, height: 1.1),
                    ),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(children: [
                          Icon(Icons.access_time_rounded, size: 12, color: Colors.white.withValues(alpha: 0.4)),
                          const SizedBox(width: 5),
                          Text(details.timezone, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF00FF00), shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text('ON AIR', style: GoogleFonts.outfit(color: const Color(0xFF00FF00), fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 28),

                    // Watch Live button â€” premium full-width
                    GestureDetector(
                      onTap: () {
                        if (widget.channel.code != null && widget.channel.code!.trim().isNotEmpty) {
                          _handlePlayback(widget.channel.name, widget.channel.code!);
                        } else if (widget.channel.url.isNotEmpty) {
                          _playChannelFromUrl(widget.channel.url);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No stream available for this channel')));
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFB561), Color(0xFFFF8C00)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFFFFB561).withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
                          ],
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Text('Watch Live', style: GoogleFonts.outfit(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Divider
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
                child: Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),

            // Live Now section
            if (details.liveNow != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 4, height: 20, decoration: BoxDecoration(color: const Color(0xFF00FF00), borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      Text('On Now', style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 16),
                    _buildLiveNowCard(details.liveNow!),
                  ]),
                ),
              ),

            // Upcoming section
            if (details.upcoming.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  child: Row(children: [
                    Container(width: 4, height: 20, decoration: BoxDecoration(color: const Color(0xFFFFB561), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Text('Up Next', style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),

            if (details.upcoming.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _buildUpcomingCard(details.upcoming[i], i, details.upcoming.length),
                    childCount: details.upcoming.length,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildLiveNowCard(EpgProgram program) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF00FF00).withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFF00FF00).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF00FF00), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('LIVE', style: GoogleFonts.outfit(color: const Color(0xFF00FF00), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ]),
          ),
          const Spacer(),
          Text(program.time, style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 14),
        Text(program.title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        if (program.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(program.description, style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.45), fontSize: 14, height: 1.55)),
        ],
        const SizedBox(height: 20),
        // Progress bar
        Stack(children: [
          Container(height: 5, width: double.infinity, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(3))),
          FractionallySizedBox(
            widthFactor: (program.progressPct / 100).clamp(0.0, 1.0),
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF00FF00), Color(0xFF7FFF00)]),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [BoxShadow(color: const Color(0xFF00FF00).withValues(alpha: 0.4), blurRadius: 6)],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${program.progressPct}% complete', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11)),
          Text('Remaining: ${100 - program.progressPct}%', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _buildUpcomingCard(EpgProgram program, int index, int total) {
    final isLast = index == total - 1;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Timeline
        Column(children: [
          Container(
            width: 10, height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
          ),
          if (!isLast)
            Expanded(child: Container(width: 1, color: Colors.white.withValues(alpha: 0.06), margin: const EdgeInsets.symmetric(vertical: 4))),
        ]),
        const SizedBox(width: 18),
        // Card
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(program.time, style: GoogleFonts.outfit(color: const Color(0xFFFFB561).withValues(alpha: 0.75), fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(program.title, style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              if (program.description.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(program.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.3), fontSize: 13, height: 1.4)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _handlePlayback(String name, String code) async {
    // Show loading state
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFB561)),
      ),
    );

    try {
      final streamData = await _service.fetchStreamData(name, code);
      if (mounted) Navigator.pop(context); // Close loader

      if (streamData == null) {
        if (mounted) AppToast.show(context, 'Failed to fetch stream', icon: Icons.error_rounded);
        return;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(
              title: name,
              episodeTitle: 'Live TV',
              mediaUrl: streamData.url,
              httpMetadata: {
                'direct': {
                  'headers': streamData.headers,
                }
              },
              isLiveTv: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppToast.show(context, 'Error: $e', icon: Icons.error_rounded);
      }
    }
  }
}
