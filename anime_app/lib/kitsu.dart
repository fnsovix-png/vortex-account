import 'dart:convert';

import 'package:http/http.dart' as http;

class EpisodeInfo {
  final int number;
  final String title;
  final String synopsis;
  final String thumbnail;

  const EpisodeInfo(this.number, this.title, this.synopsis, this.thumbnail);
}

class ShowExtras {
  final Map<int, EpisodeInfo> episodes;
  final Set<String> subs;
  final Set<String> dubs;

  const ShowExtras(this.episodes, this.subs, this.dubs);

  static const _names = {'en': 'English', 'ja': 'Japanese', 'es': 'Spanish', 'pt': 'Portuguese', 'fr': 'French', 'de': 'German', 'it': 'Italian', 'ko': 'Korean', 'zh': 'Chinese', 'ru': 'Russian', 'ar': 'Arabic'};

  static String _list(Set<String> codes) => (codes.map((c) => _names[c.split('-').first.toLowerCase()]).whereType<String>().toSet().toList()..sort()).join(', ');

  String get subLabel => _list(subs);
  String get dubLabel => _list(dubs);
}

/// Kitsu's public API adds episode titles, thumbnails and sub and dub details. If it's down,
/// the rest of Vortex keeps working and only these extras are missing.
class Kitsu {
  static const _base = 'https://kitsu.io/api/edge';
  static final _cache = <String, ShowExtras>{};
  static DateTime? lastOk;
  static String? lastError;

  static Future<Map<String, dynamic>> _get(String path, Map<String, String> query, {int attempt = 0}) async {
    try {
      final res = await http.get(Uri.parse('$_base$path').replace(queryParameters: query), headers: const {'Accept': 'application/vnd.api+json'}).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw 'status ${res.statusCode}';
      lastOk = DateTime.now();
      lastError = null;
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      if (attempt < 1) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return _get(path, query, attempt: attempt + 1);
      }
      lastError = 'Not answering right now. Episode titles and sub and dub details may be missing.';
      rethrow;
    }
  }

  static Future<void> ping() => _get('/anime', const {'page[limit]': '1', 'fields[anime]': 'canonicalTitle'});

  /// Returns null if Kitsu doesn't know this show or can't be reached.
  static Future<ShowExtras?> forShow(int anilistId, {int from = 0}) async {
    final key = '$anilistId-${from ~/ 40}';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final mapping = await _get('/mappings', {'filter[externalSite]': 'anilist/anime', 'filter[externalId]': '$anilistId', 'include': 'item'});
      final included = (mapping['included'] ?? const []) as List;
      if (included.isEmpty) return null;
      final id = included.first['id'] as String;
      final offset = (from ~/ 40) * 40;
      final pages = await Future.wait([
        for (final o in [offset, offset + 20]) _get('/anime/$id/episodes', {'page[limit]': '20', 'page[offset]': '$o', 'sort': 'number'}),
      ]);
      final episodes = <int, EpisodeInfo>{};
      for (final page in pages) {
        for (final e in (page['data'] ?? const []) as List) {
          final a = e['attributes'] as Map<String, dynamic>;
          final number = a['number'];
          if (number is! int) continue;
          episodes[number] = EpisodeInfo(number, (a['canonicalTitle'] as String?) ?? '', (a['synopsis'] as String?) ?? '', ((a['thumbnail'] as Map?)?['original'] as String?) ?? '');
        }
      }
      final links = await _get('/anime/$id/streaming-links', const {'page[limit]': '20'});
      final subs = <String>{}, dubs = <String>{};
      for (final l in (links['data'] ?? const []) as List) {
        subs.addAll(((l['attributes']['subs'] ?? const []) as List).cast<String>());
        dubs.addAll(((l['attributes']['dubs'] ?? const []) as List).cast<String>());
      }
      final extras = ShowExtras(episodes, subs, dubs);
      _cache[key] = extras;
      return extras;
    } catch (_) {
      return null;
    }
  }
}
