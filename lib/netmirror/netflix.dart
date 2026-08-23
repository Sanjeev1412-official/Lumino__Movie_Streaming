// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const baseUrl = "https://net51.cc";

/* ---------------- COOKIE STORE ---------------- */

class CookieStore {
  static const _key = "t_hash_t";

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> save(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, v);
  }
}

/* ---------------- EXTRACTOR PAGE ---------------- */

class ExtractorPage extends StatefulWidget {
  const ExtractorPage({super.key});

  @override
  State<ExtractorPage> createState() => _ExtractorPageState();
}

class _ExtractorPageState extends State<ExtractorPage> {
  final titleCtrl = TextEditingController();
  final seasonCtrl = TextEditingController();
  final episodeCtrl = TextEditingController();

  bool loading = false;
  String status = "";
  List<Map<String, String>> links = [];

  /* ---------- helpers ---------- */

  Future<void> _initSession() async {
    final res = await http.post(Uri.parse("$baseUrl/tv/p.php"));
    final cookie = res.headers['set-cookie'];
    if (cookie != null && cookie.contains("t_hash_t")) {
      final v = cookie.split("t_hash_t=").last.split(";").first;
      await CookieStore.save(v);
    }
  }

  Future<Map<String, String>> _headers() async {
    final cookie = await CookieStore.get();
    return {
      "User-Agent":
          "Mozilla/5.0 (Linux; Android 13; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36",
      "Referer": "$baseUrl/tv/home",
      if (cookie != null) "Cookie": "t_hash_t=$cookie; ott=nf; hd=on",
    };
  }

  /* ---------- core logic ---------- */

  Future<void> extract() async {
    final query = titleCtrl.text.trim();
    final seasonNum = int.tryParse(seasonCtrl.text.trim());
    final episodeNum = int.tryParse(episodeCtrl.text.trim());

    if (query.isEmpty) return;

    setState(() {
      loading = true;
      status = "initializing session…";
      links.clear();
    });

    await _initSession();
    final headers = await _headers();

    /* ---------- SEARCH ---------- */
    status = "searching…";
    setState(() {});

    final searchRes = await http.get(
      Uri.parse("$baseUrl/search.php?s=$query"),
      headers: headers,
    );
    final searchJson = json.decode(searchRes.body);

    final results = searchJson["searchResult"];
    if (results == null || results.isEmpty) {
      setState(() {
        loading = false;
        status = "no results found";
      });
      return;
    }

    final seriesId = results[0]["id"];

    /* ---------- POST (REAL TITLE + SEASONS) ---------- */
    status = "loading metadata…";
    setState(() {});

    final postRes = await http.get(
      Uri.parse("$baseUrl/post.php?id=$seriesId"),
      headers: headers,
    );
    final postJson = json.decode(postRes.body);

    final realTitle = postJson["title"];

    /* ---------- MOVIE ---------- */
    if (seasonNum == null || episodeNum == null) {
      await _extractPlaylist(seriesId, realTitle, headers);
      return;
    }

    /* ---------- MAP SEASON ---------- */
    String? seasonId;
    for (final s in postJson["season"]) {
      final sn = int.parse(s["s"].replaceAll("S", ""));
      if (sn == seasonNum) {
        seasonId = s["id"];
        break;
      }
    }

    if (seasonId == null) {
      setState(() {
        loading = false;
        status = "season $seasonNum not found";
      });
      return;
    }

    /* ---------- EPISODES ---------- */
    status = "finding episode…";
    setState(() {});

    String? episodeId;
    int page = 1;

    while (true) {
      final epRes = await http.get(
        Uri.parse(
            "$baseUrl/episodes.php?s=$seasonId&series=$seriesId&page=$page"),
        headers: headers,
      );
      final epJson = json.decode(epRes.body);

      for (final e in epJson["episodes"] ?? []) {
        final ep = int.parse(e["ep"].replaceAll("E", ""));
        if (ep == episodeNum) {
          episodeId = e["id"];
          break;
        }
      }

      if (episodeId != null) break;
      if (epJson["nextPageShow"] == 0) break;
      page++;
    }

    if (episodeId == null) {
      setState(() {
        loading = false;
        status = "episode not found";
      });
      return;
    }

    /* ---------- ACTIVATE EPISODE CONTEXT ---------- */
    await http.get(
      Uri.parse("$baseUrl/episode.php?id=$episodeId"),
      headers: headers,
    );

    /* ---------- PLAYLIST ---------- */
    await _extractPlaylist(episodeId, realTitle, headers);
  }

  Future<void> _extractPlaylist(
    String id,
    String title,
    Map<String, String> headers,
  ) async {
    status = "extracting video urls…";
    setState(() {});

    final playlistRes = await http.get(
      Uri.parse("$baseUrl/tv/playlist.php?id=$id&t=$title"),
      headers: headers,
    );
    final playlistJson = json.decode(playlistRes.body);

    final extracted = <Map<String, String>>[];

    for (final item in playlistJson) {
      for (final src in item["sources"]) {
        final fixed =
            "$baseUrl${src["file"].replaceFirst("/tv/", "/")}";
        extracted.add({
          "label": src["label"] ?? "unknown",
          "url": fixed,
        });
      }
    }

    setState(() {
      links = extracted;
      loading = false;
      status = extracted.isEmpty
          ? "no playable urls"
          : "extracted ${extracted.length} urls";
    });
  }

  /* ---------- UI ---------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("netflix mirror extractor")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                hintText: "movie / tv show name",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: seasonCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: "season",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: episodeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: "episode",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: loading ? null : extract,
              child: const Text("extract"),
            ),
            const SizedBox(height: 12),
            if (loading) const LinearProgressIndicator(),
            if (status.isNotEmpty) Text(status),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: links.length,
                itemBuilder: (c, i) {
                  final l = links[i];
                  return ListTile(
                    title: Text(l["label"]!),
                    subtitle: Text(l["url"]!, maxLines: 2),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: l["url"]!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("url copied")),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
