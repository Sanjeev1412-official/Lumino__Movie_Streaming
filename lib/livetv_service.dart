// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;

class LiveTvChannel {
  final String? code;
  final String? image;
  final String name;
  final String status;
  final String url;
  final int viewers;

  LiveTvChannel({
    this.code,
    this.image,
    required this.name,
    required this.status,
    required this.url,
    required this.viewers,
  });

  factory LiveTvChannel.fromJson(Map<String, dynamic> json) {
    String rawName = json['name'] ?? json['channel_name'] ?? 'Unknown Channel';
    String cleanedName = rawName.replaceAll(RegExp(r'\s*\[.*?\]'), '').replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

    return LiveTvChannel(
      code: json['code'] ?? json['channel_code'],
      image: json['image'],
      name: cleanedName,
      status: json['status'] ?? 'online',
      url: json['url'] ?? '',
      viewers: json['viewers'] ?? 0,
    );
  }

  bool get isOnline => status.toLowerCase() == 'online';
}

class LiveTvEvent {
  final String event;
  final String status;
  final String start;
  final String end;
  final String? eventImg;
  final String tournament;
  final String? country;
  final String? gameID;
  final String category;
  final String? homeTeam;
  final String? awayTeam;
  final String? homeTeamIMG;
  final String? awayTeamIMG;
  final List<LiveTvChannel> channels;

  LiveTvEvent({
    required this.event,
    required this.status,
    required this.start,
    required this.end,
    this.eventImg,
    required this.tournament,
    this.country,
    this.gameID,
    required this.category,
    this.homeTeam,
    this.awayTeam,
    this.homeTeamIMG,
    this.awayTeamIMG,
    required this.channels,
  });

  factory LiveTvEvent.fromJson(Map<String, dynamic> json) {
    var list = json['channels'] as List? ?? [];
    List<LiveTvChannel> channelList = list.map((i) => LiveTvChannel.fromJson(i)).toList();

    String resolvedEvent = 'Unknown Event';
    if (json['event'] != null && json['event'].toString().trim().isNotEmpty) {
      resolvedEvent = json['event'];
    } else if (json['homeTeam'] != null && json['homeTeam'].toString().trim().isNotEmpty && json['awayTeam'] != null && json['awayTeam'].toString().trim().isNotEmpty) {
      resolvedEvent = "${json['homeTeam']} vs ${json['awayTeam']}";
    }

    return LiveTvEvent(
      event: resolvedEvent,
      status: json['status'] ?? 'upcoming',
      start: json['start'] ?? '',
      end: json['end'] ?? '',
      eventImg: json['eventIMG'] ?? json['homeTeamIMG'],
      tournament: json['tournament'] ?? 'Sports',
      country: json['country'],
      gameID: json['gameID']?.toString(),
      category: json['category'] ?? 'Sports',
      homeTeam: json['homeTeam'],
      awayTeam: json['awayTeam'],
      homeTeamIMG: json['homeTeamIMG'],
      awayTeamIMG: json['awayTeamIMG'],
      channels: channelList,
    );
  }

  bool get isUpcoming => ['ns', 'upcoming', 'not started', 'tba'].contains(status.toLowerCase());
  bool get isFinished => ['ft', 'finished', 'canc', 'pst', 'abandoned', 'ended', 'aot', 'aet'].contains(status.toLowerCase());
  bool get isLive => status.isNotEmpty && !isUpcoming && !isFinished;

  String get displayStatus {
    if (isLive) return 'LIVE';
    if (isUpcoming) return 'UPCOMING';
    if (isFinished) return 'FINISHED';
    return status.toUpperCase();
  }
}

class EpgProgram {
  final String title;
  final String description;
  final String start;
  final String stop;
  final String time;
  final int progressPct;

  EpgProgram({
    required this.title,
    required this.description,
    required this.start,
    required this.stop,
    required this.time,
    this.progressPct = 0,
  });

  factory EpgProgram.fromJson(Map<String, dynamic> json) {
    return EpgProgram(
      title: json['title'] ?? 'No Title',
      description: json['description'] ?? '',
      start: json['start'] ?? '',
      stop: json['stop'] ?? '',
      time: json['time'] ?? '',
      progressPct: json['progress_pct'] ?? 0,
    );
  }
}

class ChannelDetails {
  final String name;
  final String logoUrl;
  final String playerUrl;
  final String timezone;
  final EpgProgram? liveNow;
  final List<EpgProgram> upcoming;

  ChannelDetails({
    required this.name,
    required this.logoUrl,
    required this.playerUrl,
    required this.timezone,
    this.liveNow,
    required this.upcoming,
  });

  factory ChannelDetails.fromJson(Map<String, dynamic> json) {
    final epg = json['epg'] as Map<String, dynamic>?;
    final liveNowJson = epg?['live_now'];
    final upcomingList = epg?['upcoming'] as List? ?? [];

    return ChannelDetails(
      name: json['name'] ?? '',
      logoUrl: json['logo_url'] ?? '',
      playerUrl: json['player_url'] ?? '',
      timezone: json['timezone'] ?? 'UTC',
      liveNow: liveNowJson != null ? EpgProgram.fromJson(liveNowJson) : null,
      upcoming: upcomingList.map((e) => EpgProgram.fromJson(e)).toList(),
    );
  }
}

class LiveStreamData {
  final String url;
  final Map<String, String> headers;
  final String name;

  LiveStreamData({
    required this.url,
    required this.headers,
    required this.name,
  });

  factory LiveStreamData.fromJson(Map<String, dynamic> json) {
    final headers = Map<String, String>.from(json['headers'] ?? {});
    return LiveStreamData(
      url: json['stream_url'] ?? '',
      headers: headers,
      name: json['name'] ?? '',
    );
  }
}

class LiveTvService {
  static const String _homeUrl = 'https://sanjeev1412-livetv-api.hf.space/home';
  static const String _eventUrl = 'https://sanjeev1412-livetv-api.hf.space/event';
  static const String _detailsUrl = 'https://sanjeev1412-livetv-api.hf.space/details';
  static const String _streamUrl = 'https://sanjeev1412-livetv-api.hf.space/stream';

  Future<List<LiveTvChannel>> fetchChannels() async {
    try {
      final response = await http.get(Uri.parse(_homeUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> channelsJson = data['channels'] ?? [];
        return channelsJson.map((json) => LiveTvChannel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load channels');
      }
    } catch (e) {
      print('Error fetching live TV channels: $e');
      return [];
    }
  }

  Future<List<LiveTvEvent>> fetchEvents() async {
    try {
      final response = await http.get(Uri.parse(_eventUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        Map<String, LiveTvEvent> uniqueEvents = {};

        // Helper to process a sports map (category -> list of events)
        void processSportsMap(Map<String, dynamic> sportsMap) {
          sportsMap.forEach((category, events) {
            if (events is List) {
              for (var eventJson in events) {
                if (eventJson is Map<String, dynamic>) {
                  String? eventName = eventJson['event'];
                  if (eventName == null || eventName.trim().isEmpty) {
                    if (eventJson['homeTeam'] != null && eventJson['homeTeam'].toString().trim().isNotEmpty && eventJson['awayTeam'] != null && eventJson['awayTeam'].toString().trim().isNotEmpty) {
                      eventName = "${eventJson['homeTeam']} vs ${eventJson['awayTeam']}";
                    }
                  }
                  if (eventName == null || eventName.trim().isEmpty) continue;

                  eventJson['category'] = category;
                  final event = LiveTvEvent.fromJson(eventJson);
                  final String key = event.gameID ?? '${event.event}_${event.start}';
                  
                  if (!uniqueEvents.containsKey(key)) {
                    uniqueEvents[key] = event;
                  } else {
                    for (var channel in event.channels) {
                      if (!uniqueEvents[key]!.channels.any((c) => c.url == channel.url)) {
                        uniqueEvents[key]!.channels.add(channel);
                      }
                    }
                  }
                }
              }
            }
          });
        }

        // Process cdn-live-tv specifically if it exists
        if (data.containsKey('cdn-live-tv') && data['cdn-live-tv'] is Map) {
          processSportsMap(data['cdn-live-tv']);
        }

        // Scan everything else (some categories like Soccer might be at the root or in other maps)
        data.forEach((key, value) {
          if (key == 'cdn-live-tv') return;
          
          if (value is List) {
            for (var eventJson in value) {
              if (eventJson is Map<String, dynamic>) {
                String? eventName = eventJson['event'];
                if (eventName == null || eventName.trim().isEmpty) {
                  if (eventJson['homeTeam'] != null && eventJson['homeTeam'].toString().trim().isNotEmpty && eventJson['awayTeam'] != null && eventJson['awayTeam'].toString().trim().isNotEmpty) {
                    eventName = "${eventJson['homeTeam']} vs ${eventJson['awayTeam']}";
                  }
                }
                if (eventName == null || eventName.trim().isEmpty) continue;
                eventJson['category'] = key;
                final event = LiveTvEvent.fromJson(eventJson);
                final String k = event.gameID ?? '${event.event}_${event.start}';
                if (!uniqueEvents.containsKey(k)) uniqueEvents[k] = event;
              }
            }
          } else if (value is Map<String, dynamic>) {
            processSportsMap(value);
          }
        });
        
        List<LiveTvEvent> allEvents = uniqueEvents.values.toList();
        allEvents = allEvents.where((e) => e.event != 'Unknown Event' && e.event.isNotEmpty).toList();

        allEvents.sort((a, b) {
          if (a.isLive && !b.isLive) return -1;
          if (!a.isLive && b.isLive) return 1;
          if (a.isUpcoming && b.isFinished) return -1;
          if (a.isFinished && b.isUpcoming) return 1;
          return 0;
        });

        return allEvents;
      } else {
        throw Exception('Failed to load events');
      }
    } catch (e) {
      print('Error fetching live events: $e');
      return [];
    }
  }

  Future<ChannelDetails?> fetchChannelDetails(String name, String code) async {
    try {
      final encodedName = Uri.encodeComponent(name);
      final url = '$_detailsUrl?name=$encodedName&code=$code';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return ChannelDetails.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Error fetching channel details: $e');
      return null;
    }
  }

  Future<LiveStreamData?> fetchStreamData(String name, String code) async {
    try {
      String cleanedName = name.replaceAll(RegExp(r'\s*\[.*?\]'), '').replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();
      final encodedName = Uri.encodeComponent(cleanedName);
      final url = '$_streamUrl?name=$encodedName&code=$code';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return LiveStreamData.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Error fetching stream data: $e');
      return null;
    }
  }
}


