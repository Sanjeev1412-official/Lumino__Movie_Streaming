// ignore_for_file: avoid_print
// lib/services/world4ufree_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
// not used directly, but base64 is in dart:convert

class World4uFreeService {
  static const String baseUrl = "https://world4ufree.onl";
  static final Map<String, String> headers = {
    "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Referer": baseUrl,
  };

  static final RegExp qualityRegExp = RegExp(
    r"(4k|2160p|1080p|720p|480p)",
    caseSensitive: false,
  );
  static final RegExp redirectRegExp = RegExp(
    r"window\.location\.href\s*=\s*'([^']+)'",
  );
  static final List<String> patterns = [
    "@\$",
    "^^",
    "~@",
    "%?",
    "*~",
    "!!",
    "#&",
  ];

  // ------------------ Crypto Helpers ------------------
  static String rot13(String s) {
    final buffer = StringBuffer();
    for (var c in s.runes) {
      final char = String.fromCharCode(c);
      if ('a'.codeUnitAt(0) <= c && c <= 'z'.codeUnitAt(0)) {
        buffer.write(
          String.fromCharCode(
            (c - 'a'.codeUnitAt(0) + 13) % 26 + 'a'.codeUnitAt(0),
          ),
        );
      } else if ('A'.codeUnitAt(0) <= c && c <= 'Z'.codeUnitAt(0)) {
        buffer.write(
          String.fromCharCode(
            (c - 'A'.codeUnitAt(0) + 13) % 26 + 'A'.codeUnitAt(0),
          ),
        );
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static String replacePatterns(String s) {
    for (var p in patterns) {
      s = s.replaceAll(p, "_");
    }
    return s;
  }

  static String removeUnderscores(String s) => s.replaceAll("_", "");

  static String charShift(String s, int shift) {
    return s.runes.map((c) => String.fromCharCode(c - shift)).join();
  }

  static Map<String, dynamic> decryptF7(String encoded) {
    try {
      var v1 = rot13(encoded);
      var v2 = replacePatterns(v1);
      var v3 = removeUnderscores(v2);
      var v4 = utf8.decode(base64.decode(v3));
      var v5 = charShift(v4, 3);
      var v6 = v5.split('').reversed.join();
      var v7 = utf8.decode(base64.decode(v6));
      return json.decode(v7) as Map<String, dynamic>;
    } catch (e) {
      print("Decryption error: $e");
      return {};
    }
  }

  // -------------------- STEP 1: SEARCH --------------------
  // -------------------- STEP 1: SEARCH (UPDATED) --------------------
  static Future<String?> getFirstMovieUrl(String movieName) async {
    String sanitizedMovieName = movieName.replaceAll(
      RegExp(r"[^a-zA-Z0-9\s]"),
      "",
    );

    final searchUrl = "$baseUrl/?s=${Uri.encodeComponent(sanitizedMovieName)}";
    print("[search] $searchUrl");

    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse(searchUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final document = parse(response.body);

      // Collect all result figures
      final List<Map<String, String>> candidates = [];
      final figures = document.querySelectorAll(
        'section.home-wrapper .thumb figure',
      );
      for (var figure in figures) {
        final img = figure.querySelector('img');
        final title = img?.attributes['title'] ?? '';
        if (title.isEmpty) continue;

        // Prefer the main link inside figcaption, fall back to the hover a
        var link = figure.querySelector('figcaption a')?.attributes['href'];
        if (link == null || link.isEmpty) {
          link = figure.querySelector('a[href]')?.attributes['href'];
        }
        if (link != null && link.startsWith('http')) {
          candidates.add({'title': title.toLowerCase(), 'url': link});
        }
      }

      if (candidates.isEmpty) return null;

      // Helper to check language count
      int countLanguages(String t) {
        final langs = [
          'tamil',
          'malayalam',
          'telugu',
          'kannada',
          'hindi',
          'english',
        ];
        return langs.where((l) => t.contains(l)).length;
      }

      // First: non-PreDVDRip candidates
      var filtered = candidates
          .where((c) => !c['title']!.contains('predvdrip'))
          .toList();

      String? selectedUrl;
      if (filtered.isNotEmpty) {
        // Prefer pure/single Malayalam (1 language = malayalam)
        var malayalamOnly = filtered.where((c) {
          final langs = countLanguages(c['title']!);
          return langs == 1 && c['title']!.contains('malayalam');
        });
        if (malayalamOnly.isNotEmpty) {
          selectedUrl = malayalamOnly.first['url'];
        } else {
          // Prefer any with Malayalam (even multi)
          var withMalayalam = filtered.where(
            (c) => c['title']!.contains('malayalam'),
          );
          if (withMalayalam.isNotEmpty) {
            selectedUrl = withMalayalam.first['url'];
          } else {
            // Fallback to first non-PreDVDRip
            selectedUrl = filtered.first['url'];
          }
        }
      } else {
        // No non-PreDVDRip → allow PreDVDRip, same priority logic
        var predvd = candidates;
        var malayalamOnly = predvd.where((c) {
          final langs = countLanguages(c['title']!);
          return langs == 1 && c['title']!.contains('malayalam');
        });
        if (malayalamOnly.isNotEmpty) {
          selectedUrl = malayalamOnly.first['url'];
        } else {
          var withMalayalam = predvd.where(
            (c) => c['title']!.contains('malayalam'),
          );
          if (withMalayalam.isNotEmpty) {
            selectedUrl = withMalayalam.first['url'];
          } else {
            selectedUrl = predvd.first['url'];
          }
        }
      }

      print("[selected] $selectedUrl");
      return selectedUrl;
    } catch (e) {
      print("Search error: $e");
      return null;
    } finally {
      client.close();
    }
  }

  // -------------------- STEP 2: MULTI LINK 1 --------------------
  static Future<Map<String, String>> extractMultiLink1(
    String moviePageUrl,
  ) async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse(moviePageUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return {};

      final document = parse(response.body);
      final Map<String, String> results = {};

      for (var a in document.querySelectorAll("a.buttn.direct")) {
        final text = a.text
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase();
        if (!text.contains("multi link 1")) continue;

        final match = qualityRegExp.firstMatch(text);
        if (match == null) continue;

        final quality = match.group(1)!.toUpperCase();
        final href = a.attributes['href'];
        if (href != null) results[quality] = href;
      }
      return results;
    } catch (e) {
      print("Multi link error: $e");
      return {};
    } finally {
      client.close();
    }
  }

  // -------------------- STEP 3: UPTOBHAI → VOE --------------------
  static Future<String?> extractVoeFromUptobhai(String url) async {
    final client = http.Client();
    try {
      await client.get(Uri.parse(url), headers: headers); // initial GET
      final postResponse = await client
          .post(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      final document = parse(postResponse.body);
      for (var a in document.querySelectorAll("div.view-well a[href]")) {
        final href = a.attributes['href'];
        if (href != null && href.contains("voe.sx")) {
          return href;
        }
      }
      return null;
    } catch (e) {
      print("Uptobhai error: $e");
      return null;
    } finally {
      client.close();
    }
  }

  // ------------------ VOE Domain Conversion ------------------
  static String convertVoeToCurrentDomain(String voeUrl) {
    // Replaces voe.sx with the current anti-adblock bypass domain (as of Dec 2025)
    return voeUrl.replaceFirst("voe.sx", "walterprettytheir.com");
  }

  // -------------------- STEP 4: VOE → M3U8 --------------------
  static Future<Map<String, dynamic>> extractVoe(
    String url, {
    String? referer,
  }) async {
    final client = http.Client();
    try {
      Map<String, String> reqHeaders = Map.from(headers);
      if (referer != null) reqHeaders["Referer"] = referer;

      var response = await client
          .get(Uri.parse(url), headers: reqHeaders)
          .timeout(const Duration(seconds: 15));

      // Handle JS redirect
      final redirectMatch = redirectRegExp.firstMatch(response.body);
      if (redirectMatch != null) {
        response = await client.get(
          Uri.parse(redirectMatch.group(1)!),
          headers: reqHeaders,
        );
      }

      final document = parse(response.body);
      final script = document.querySelector('script[type="application/json"]');
      if (script == null || script.innerHtml.trim().isEmpty) {
        throw Exception("application/json script not found");
      }

      String data = script.innerHtml.trim();
      if (!data.startsWith('["') || !data.endsWith('"]')) {
        throw Exception("unexpected voe json wrapper");
      }

      final encoded = data.substring(2, data.length - 2);
      final decrypted = decryptF7(encoded);

      return {
        "m3u8": decrypted["source"],
        "mp4": decrypted["direct_access_url"],
        "raw": decrypted,
      };
    } catch (e) {
      print("VOE extract error: $e");
      return {};
    } finally {
      client.close();
    }
  }

  // -------------------- MAIN FUNCTION --------------------
  static Future<Map<String, String>> getMovieLinks(String movieName) async {
    final movieUrl = await getFirstMovieUrl(movieName);
    if (movieUrl == null) {
      print("[exit] movie not found");
      return {};
    }

    final qualityLinks = await extractMultiLink1(movieUrl);
    final Map<String, String> voeLinks = {};

    for (var entry in qualityLinks.entries) {
      final voe = await extractVoeFromUptobhai(entry.value);
      if (voe != null) {
        voeLinks[entry.key] = voe;
      }
    }

    final Map<String, String> finalResults = {};

    for (var entry in voeLinks.entries) {
      final convertedUrl = convertVoeToCurrentDomain(entry.value);
      final voeData = await extractVoe(convertedUrl, referer: baseUrl);
      final url = voeData["mp4"] ?? voeData["m3u8"];
      if (url != null) {
        finalResults[entry.key] = url as String;
      }
    }

    return finalResults;
  }
}
