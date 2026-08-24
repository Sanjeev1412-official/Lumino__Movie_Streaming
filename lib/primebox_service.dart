// ignore_for_file: unused_local_variable
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:lumino_app_moviestreaming/config/env_config.dart';

String get _baseUrl => EnvConfig.lambdaUrl;

class PrimeboxItem {
  final String type;
  final int subjectType;
  final String title;
  final String year;
  final String rating;
  final String quality;
  final String link;
  final String? posterPath;
  final int? subjectId;
  final String detailPath;

  PrimeboxItem({
    required this.type,
    required this.subjectType,
    this.subjectId,
    required this.title,
    required this.year,
    required this.rating,
    required this.quality,
    required this.link,
    this.posterPath,
    required this.detailPath,
  });

  factory PrimeboxItem.fromJson(Map<String, dynamic> json) {
    final title = json['title'] ?? 'N/A';
    final detailPath = json['detailPath'] ?? '';
    final subjectType = json['subjectType'] is int ? json['subjectType'] : 1;
    final subjectIdRaw = json['subjectId'] ?? json['subject_id'] ?? json['id'];
    final subjectId = subjectIdRaw != null ? int.tryParse(subjectIdRaw.toString()) : null;
    final cover = json['cover'] is Map ? json['cover'] : {};
    final image = cover['url'];

    // Improved metadata extraction
    String yearStr = 'N/A';
    final relDate = json['releaseDate'] ?? json['release_date'];
    if (relDate != null && relDate.toString().length >= 4) {
      yearStr = relDate.toString().substring(0, 4);
    } else if (json['year'] != null) {
      yearStr = json['year'].toString();
    }

    final ratingStr = json['imdbRate']?.toString() ?? json['score']?.toString() ?? 'N/A';
    final qualityStr = json['quality']?.toString() ?? 'HD';

    return PrimeboxItem(
      type: subjectType == 1 ? 'Movie' : 'Series',
      subjectType: subjectType,
      subjectId: subjectId,
      title: title,
      year: yearStr,
      rating: ratingStr,
      quality: qualityStr,
      link: detailPath.isNotEmpty ? '$_baseUrl/detail/$detailPath' : '',
      posterPath: image,
      detailPath: detailPath,
    );
  }
}

class PrimeboxService {
  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36',
  };

  static final Map<String, String> _netfilmHeaders = {
    'accept': 'application/json',
    'accept-language': 'en-US,en;q=0.9,ml;q=0.8',
    'cookie': r'Lda_aKUr6BGRn=hipodi.com/r/v2?; Lda_aKUr6BGRr=0; _ga=GA1.1.1947013705.1778379556; token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1aWQiOjQwNTIzNjQ4Mjk3MjczNzkzMjgsImF0cCI6MywiZXh0IjoiMTc3ODM3OTU4MSIsImV4cCI6MTc4NjE1NTU4MSwiaWF0IjoxNzc4Mzc5MjgxfQ.CmrHaS0ckZ-qf1E4pvJe2glb3cVgVPVpKvnyAsTj16A; Fm_kZf8ZQvmX=1; Ac_aqK8DtrDS=7; _ga_10CEP3VR82=GS2.1.s1778379555$o1$g1$t1778379571$j44$l0$h0',
    'priority': 'u=1, i',
    'sec-ch-ua': '"Google Chrome";v="147", "Not.A/Brand";v="8", "Chromium";v="147"',
    'sec-ch-ua-mobile': '?1',
    'sec-ch-ua-platform': '"Android"',
    'sec-fetch-dest': 'empty',
    'sec-fetch-mode': 'cors',
    'sec-fetch-site': 'same-origin',
    'user-agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Mobile Safari/537.36',
    'x-client-info': '{"timezone":"Asia/Calcutta"}',
  };

  static Future<List<PrimeboxItem>> search(String query) async {
    final q = Uri.encodeQueryComponent(query.trim());
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/search?keyword=$q'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['code'] == 0) {
          final items = data['data']?['items'] as List?;
          if (items != null) {
            return items.map((m) => PrimeboxItem.fromJson(m)).toList();
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Primebox search error: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>> getStreams({
    required String detailUrl,
    required int subjectType,
    int? subjectIdIn, // OPTIONAL: if we already have it
    int? season,
    int? episode,
  }) async {
    final empty = <String, dynamic>{
      'streams': <String, dynamic>{},
      'subtitles': <String, List<String>>{},
    };

    try {
      if (detailUrl.isEmpty) return empty;

    String detailPath = detailUrl;
    if (detailPath.contains('/detail/')) {
      detailPath = detailPath.split('/detail/').last;
    } else if (detailPath.contains('detailPath=')) {
      detailPath = detailPath.split('detailPath=').last;
    }
    // Clean any remaining query params if they exist
    if (detailPath.contains('?')) {
      detailPath = detailPath.split('?').first;
    }
    if (detailPath.contains('&')) {
      detailPath = detailPath.split('&').first;
    }

    final List<String> baseUrls = [
      EnvConfig.lambdaUrl,
    ];

    String? currentSubjectId;
    List<Map<String, dynamic>> dubsToFetch = [];
    final interestingLangs = [
      'original audio',
      'english',
      'malayalam',
      'tamil',
      'telugu',
      'hindi'
    ];

    // 1. Resolve ID and find Dubs
    // Try the new h5-api first as requested
    final detailApi = 'https://h5-api.aoneroom.com/wefeed-h5api-bff/detail?detailPath=$detailPath';
    if (kDebugMode) print('[Primebox] Fetching detail (aoneroom): $detailApi');
    try {
      final res = await http
          .get(Uri.parse(detailApi), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['code'] == 0) {
          final dData = data['data'] ?? {};
          final subject = dData['subject'] ?? {};
          
          final rawId = subject['subjectId'] ??
              subject['subject_id'] ??
              dData['subjectId'] ??
              dData['id'];
          currentSubjectId = rawId?.toString();

          // Extract interesting dubs from subject
          final dubs = subject['dubs'] as List?;
          if (dubs != null) {
            for (var dub in dubs) {
              final lanName = dub['lanName']?.toString() ?? '';
              final lowerLan = lanName.toLowerCase();
              if (interestingLangs.any((lang) => lowerLan.contains(lang))) {
                dubsToFetch.add({
                  'subjectId': dub['subjectId']?.toString(),
                  'detailPath': dub['detailPath']?.toString() ?? detailPath,
                  'lanName': lanName,
                });
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('[Primebox] Detail fetch exception (aoneroom): $e');
    }

    // Fallback to legacy baseUrls if aoneroom failed to find subjectId
    if (currentSubjectId == null) {
      for (String baseUrl in baseUrls) {
        final legacyApi = '$baseUrl/api/detail?detailPath=$detailPath';
        if (kDebugMode) print('[Primebox] Fetching detail (legacy): $legacyApi');
        try {
          final res = await http
              .get(Uri.parse(legacyApi), headers: _headers)
              .timeout(const Duration(seconds: 15));
          if (res.statusCode == 200) {
            final data = json.decode(res.body);
            if (data['code'] == 0) {
              final dData = data['data'] ?? {};
              final rawId = dData['subjectId'] ??
                  dData['subject_id'] ??
                  dData['subject']?['subjectId'] ??
                  dData['id'];
              currentSubjectId = rawId?.toString();

              if (dubsToFetch.isEmpty) {
                final dubs = dData['dubs'] as List?;
                if (dubs != null) {
                  for (var dub in dubs) {
                    final lanName = dub['lanName']?.toString() ?? '';
                    final lowerLan = lanName.toLowerCase();
                    if (interestingLangs.any((lang) => lowerLan.contains(lang))) {
                      dubsToFetch.add({
                        'subjectId': dub['subjectId']?.toString(),
                        'detailPath': dub['detailPath']?.toString() ?? detailPath,
                        'lanName': lanName,
                      });
                    }
                  }
                }
              }
              break;
            }
          }
        } catch (e) {
          if (kDebugMode) print('[Primebox] Detail fetch exception ($baseUrl): $e');
        }
      }
    }

    if (currentSubjectId == null && subjectIdIn != null) {
      currentSubjectId = subjectIdIn.toString();
    }

    // If no dubs found but we have a subjectId, at least fetch that one
    if (dubsToFetch.isEmpty && currentSubjectId != null) {
      dubsToFetch.add({
        'subjectId': currentSubjectId,
        'detailPath': detailPath,
        'lanName': 'Original',
      });
    }

    final streams = <String, dynamic>{};

    int se = 0;
    int ep = 0;
    if (subjectType == 2) {
      se = season ?? 1;
      ep = episode ?? 1;
    }

    // 2. Resolve which version to fetch
    String? sid;
    String? dPath;
    String? currentLan;

    // Find the explicit "Original Audio" dub first
    final Map<String, dynamic> originalDub = dubsToFetch.firstWhere(
      (d) =>
          d['lanName']?.toString().toLowerCase().contains('original') ?? false,
      orElse: () => {},
    );

    if (subjectIdIn != null && subjectIdIn != 0) {
      final requestedSid = subjectIdIn.toString();
      
      // Check if we requested a specific dub
      final Map<String, dynamic> matchedDub = dubsToFetch.firstWhere(
        (d) => d['subjectId'] == requestedSid,
        orElse: () => {},
      );

      if (matchedDub.isNotEmpty) {
        // Use the explicitly requested dub
        sid = matchedDub['subjectId'];
        dPath = matchedDub['detailPath'] ?? detailPath;
        currentLan = matchedDub['lanName'];
      } else if (originalDub.isNotEmpty) {
        // Fallback to strict original if the requested ID isn't in the dubs list
        sid = originalDub['subjectId'];
        dPath = originalDub['detailPath'] ?? detailPath;
        currentLan = originalDub['lanName'];
      } else {
        sid = requestedSid;
        dPath = detailPath;
        currentLan = 'Requested Source';
      }
    } else {
      // Initial load: STRICTLY find the "Original Audio" dub
      if (originalDub.isNotEmpty) {
        sid = originalDub['subjectId'];
        dPath = originalDub['detailPath'] ?? detailPath;
        currentLan = originalDub['lanName'];
      } else if (currentSubjectId != null) {
        sid = currentSubjectId;
        dPath = detailPath;
        currentLan = 'Original Audio';
      }
    }

    final subtitles = <String, List<String>>{};

    if (sid != null) {
      // 1. PRIMARY: fmoviesunblocked.net
      final fmoviesPlayApi = 'https://fmoviesunblocked.net/wefeed-h5-bff/web/subject/play?subjectId=$sid&se=$se&ep=$ep';
      final fmoviesReferer = 'https://fmoviesunblocked.net/spa/videoPlayPage/movies/$dPath?id=$sid&type=/movie/detail&lang=en';
      
      try {
        if (kDebugMode) print('[Primebox] Trying fmovies primary: $fmoviesPlayApi');
        final res = await http.get(
          Uri.parse(fmoviesPlayApi),
          headers: {
            ..._netfilmHeaders,
            'referer': fmoviesReferer,
          },
        ).timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final jsonRes = json.decode(res.body);
          if (jsonRes['code'] == 0) {
            final pData = jsonRes['data'] ?? {};
            final List? streamsData = (pData['streams'] is List)
                ? pData['streams']
                : (pData['list'] is List ? pData['list'] : null);

            if (streamsData != null && streamsData.isNotEmpty) {
              for (var s in streamsData) {
                final reso = s['resolutions']?.toString() ??
                    s['resolution']?.toString() ??
                    s['name']?.toString() ??
                    'auto';
                final url = s['url']?.toString() ?? '';
                if (url.isNotEmpty) {
                  streams[reso] = {
                    'url': url,
                    'id': s['id']?.toString(),
                    'format': s['format']?.toString() ?? 'MP4',
                    'subjectId': sid,
                    'detailPath': dPath,
                  };
                }
              }
              
              // If we got streams, fetch captions from fmovies
              if (streams.isNotEmpty) {
                final firstStream = streams.values.first;
                final format = firstStream['format'];
                final streamId = firstStream['id'];
                final captionApi = 'https://fmoviesunblocked.net/wefeed-h5-bff/web/subject/caption?format=$format&id=$streamId&subjectId=$sid';
                
                try {
                  final capRes = await http.get(
                    Uri.parse(captionApi),
                    headers: {
                      ..._netfilmHeaders,
                      'referer': fmoviesReferer,
                    },
                  ).timeout(const Duration(seconds: 10));
                  
                  if (capRes.statusCode == 200) {
                    final capJson = json.decode(capRes.body);
                    if (capJson['code'] == 0 && capJson['data'] is List) {
                      for (var cap in capJson['data']) {
                        final lang = cap['languageName'] ?? cap['lan'] ?? 'Unknown';
                        final capUrl = cap['url'] ?? '';
                        if (capUrl.isNotEmpty) {
                          subtitles.putIfAbsent(lang, () => []).add(capUrl);
                        }
                      }
                    }
                  }
                } catch (e) {
                  if (kDebugMode) print('[Primebox] fmovies caption fetch error: $e');
                }
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('[Primebox] fmovies primary error: $e');
      }

      // 2. FALLBACK: netfilm.world (only if fmovies failed to find streams)
      if (streams.isEmpty) {
        final netfilmPlayApi = 'https://netfilm.world/wefeed-h5api-bff/subject/play?subjectId=$sid&se=$se&ep=$ep&detailPath=$dPath';
        final netfilmReferer = 'https://netfilm.world/spa/videoPlayPage/movies/$dPath?id=$sid&type=/movie/detail&detailSe=&detailEp=&lang=en';
        
        try {
          if (kDebugMode) print('[Primebox] Falling back to netfilm: $netfilmPlayApi');
          final res = await http.get(
            Uri.parse(netfilmPlayApi),
            headers: {
              ..._netfilmHeaders,
              'referer': netfilmReferer,
            },
          ).timeout(const Duration(seconds: 15));

          if (res.statusCode == 200) {
            final jsonRes = json.decode(res.body);
            if (jsonRes['code'] == 0) {
              final pData = jsonRes['data'] ?? {};
              final List? streamsData = (pData['streams'] is List)
                  ? pData['streams']
                  : (pData['list'] is List ? pData['list'] : null);

              if (streamsData != null) {
                for (var s in streamsData) {
                  final reso = s['resolutions']?.toString() ??
                      s['resolution']?.toString() ??
                      s['name']?.toString() ??
                      'auto';
                  final url = s['url']?.toString() ?? '';
                  if (url.isNotEmpty) {
                    streams[reso] = {
                      'url': url,
                      'id': s['id']?.toString(),
                      'format': s['format']?.toString() ?? 'MP4',
                      'subjectId': sid,
                      'detailPath': dPath,
                    };
                  }
                }
                
                // Fallback subtitles from netfilm if streams were found here
                if (streams.isNotEmpty) {
                   final firstStream = streams.values.first;
                   final format = firstStream['format'];
                   final streamId = firstStream['id'];
                   final netfilmCaptionApi = 'https://netfilm.world/wefeed-h5api-bff/subject/caption?format=$format&id=$streamId&subjectId=$sid';
                   
                   try {
                     final capRes = await http.get(
                       Uri.parse(netfilmCaptionApi),
                       headers: {
                         ..._netfilmHeaders,
                         'referer': netfilmReferer,
                       },
                     ).timeout(const Duration(seconds: 10));
                     
                     if (capRes.statusCode == 200) {
                       final capJson = json.decode(capRes.body);
                       if (capJson['code'] == 0 && capJson['data'] is List) {
                         for (var cap in capJson['data']) {
                           final lang = cap['languageName'] ?? cap['lan'] ?? 'Unknown';
                           final capUrl = cap['url'] ?? '';
                           if (capUrl.isNotEmpty) {
                             subtitles.putIfAbsent(lang, () => []).add(capUrl);
                           }
                         }
                       }
                     }
                   } catch (e) {
                     if (kDebugMode) print('[Primebox] netfilm caption fetch error: $e');
                   }
                }
              }
            }
          }
        } catch (e) {
          if (kDebugMode) print('[Primebox] netfilm fallback error: $e');
        }
      }
    }

    if (streams.isEmpty) {
      if (kDebugMode) print('[Primebox] No streams found after checking all sources');
      return empty;
    }

    if (kDebugMode) print('[Primebox] Found ${streams.length} total streams');

    return {
      'streams': streams,
      'subtitles': subtitles,
      'dubs': dubsToFetch,
    };
    } catch (e) {
      if (kDebugMode) print('Primebox getStreams error: $e');
    }

    return empty;
  }
}

