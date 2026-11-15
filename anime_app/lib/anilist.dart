import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

const _card = '''
fragment Card on Media {
  id title { romaji english native } coverImage { extraLarge large color } bannerImage seasonYear startDate { year }
  format averageScore genres episodes status externalLinks { site url type language notes } nextAiringEpisode { episode airingAt }
}''';

const _detail = '''
query (\$id: Int) { Media(id: \$id, type: ANIME) {
  ...Card description(asHtml: false) season
  studios(isMain: true) { nodes { name } }
  trailer { id site }
  streamingEpisodes { title thumbnail url site }
  relations { edges { relationType node { ...Card type } } }
  recommendations(sort: RATING_DESC, perPage: 12) { nodes { mediaRecommendation { ...Card } } }
} }
$_card''';

class AniListError implements Exception {
  final String message;

  const AniListError(this.message);

  @override
  String toString() => message;
}

class HomeData {
  final List<Media> trending;
  final List<Media> airing;
  final List<Media> popular;
  final List<Media> top;
  final List<Media> upcoming;
  final List<Media> comfort;
  final List<Media> laughs;

  const HomeData(this.trending, this.airing, this.popular, this.top, this.upcoming, this.comfort, this.laughs);
}

class PageResult {
  final List<Media> items;
  final bool hasMore;

  const PageResult(this.items, this.hasMore);
}

/// AniList's public API, with caching and pacing so the app stays inside its rate limit.
class AniList {
  static void clearCache() => _cache.clear();

  /// A live check that the catalog is answering.
  static Future<void> ping() => _send('query { Page(perPage: 1) { media(type: ANIME) { id } } }', const {});

  static Future<List<Media>> byIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final data = await _ask('''
query (\$ids: [Int]) { Page(perPage: 50) { media(id_in: \$ids, type: ANIME, sort: POPULARITY_DESC, isAdult: false) { ...Card } } }
$_card''', {'ids': ids.take(50).toList()});
    return _media(data, 'Page');
  }

  static final _cache = <String, (DateTime, Map<String, dynamic>)>{};
  static Future<void> _queue = Future.value();
  static const _gap = Duration(milliseconds: 350);
  static const _keep = Duration(minutes: 10);

  static Future<Map<String, dynamic>> _ask(String query, Map<String, dynamic> variables) {
    final key = jsonEncode([query, variables]);
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _keep) return Future.value(hit.$2);
    final done = Completer<Map<String, dynamic>>();
    _queue = _queue.then((_) async {
      try {
        final data = await _send(query, variables);
        _cache[key] = (DateTime.now(), data);
        done.complete(data);
      } catch (e) {
        done.completeError(e);
      }
      await Future<void>.delayed(_gap);
    });
    return done.future;
  }

  static Future<Map<String, dynamic>> _send(String query, Map<String, dynamic> variables, {int attempt = 0}) async {
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('https://graphql.anilist.co'), headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'}, body: jsonEncode({'query': query, 'variables': variables}))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const AniListError('Check your internet connection and try again.');
    }
    if (res.statusCode == 429 && attempt < 2) {
      final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? 20;
      await Future<void>.delayed(Duration(seconds: wait.clamp(1, 60)));
      return _send(query, variables, attempt: attempt + 1);
    }
    if (res.statusCode != 200) throw const AniListError('The anime list isn\'t answering right now. Try again in a moment.');
    return (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  static List<Media> _media(Map data, String key) => [for (final m in (data[key]['media'] as List)) Media.fromJson(m)];

  static ({String season, int year}) _thisSeason() {
    final now = DateTime.now();
    final season = switch (now.month) {
      12 || 1 || 2 => 'WINTER',
      3 || 4 || 5 => 'SPRING',
      6 || 7 || 8 => 'SUMMER',
      _ => 'FALL',
    };
    return (season: season, year: now.month == 12 ? now.year + 1 : now.year);
  }

  static Future<HomeData> home() async {
    final s = _thisSeason();
    final data = await _ask('''
query (\$season: MediaSeason, \$year: Int) {
  trending: Page(perPage: 12) { media(type: ANIME, sort: TRENDING_DESC, isAdult: false) { ...Card } }
  airing: Page(perPage: 12) { media(type: ANIME, season: \$season, seasonYear: \$year, status: RELEASING, sort: POPULARITY_DESC, isAdult: false) { ...Card } }
  popular: Page(perPage: 12) { media(type: ANIME, sort: POPULARITY_DESC, isAdult: false) { ...Card } }
  top: Page(perPage: 12) { media(type: ANIME, sort: SCORE_DESC, isAdult: false) { ...Card } }
  upcoming: Page(perPage: 12) { media(type: ANIME, status: NOT_YET_RELEASED, sort: POPULARITY_DESC, isAdult: false) { ...Card } }
  comfort: Page(perPage: 12) { media(type: ANIME, genre: "Slice of Life", sort: SCORE_DESC, isAdult: false) { ...Card } }
  laughs: Page(perPage: 12) { media(type: ANIME, genre: "Comedy", sort: POPULARITY_DESC, isAdult: false) { ...Card } }
}
$_card''', {'season': s.season, 'year': s.year});
    return HomeData(_media(data, 'trending'), _media(data, 'airing'), _media(data, 'popular'), _media(data, 'top'), _media(data, 'upcoming'), _media(data, 'comfort'), _media(data, 'laughs'));
  }

  static Future<PageResult> discover({String search = '', String? genre, int? year, String? format, String? status, String sort = 'POPULARITY_DESC', List<int>? sourceIds, List<int>? onlyIds, int page = 1}) async {
    final data = await _ask('''
query (\$search: String, \$genre: String, \$year: Int, \$format: MediaFormat, \$status: MediaStatus, \$sort: [MediaSort], \$free: [Int], \$ids: [Int], \$page: Int) {
  Page(page: \$page, perPage: 24) {
    pageInfo { hasNextPage }
    media(type: ANIME, search: \$search, genre: \$genre, seasonYear: \$year, format: \$format, status: \$status, sort: \$sort, licensedById_in: \$free, id_in: \$ids, isAdult: false) { ...Card }
  }
}
$_card''', {
      if (search.isNotEmpty) 'search': search,
      'genre': ?genre,
      'year': ?year,
      'format': ?format,
      'status': ?status,
      'sort': [if (search.isNotEmpty && sort == 'POPULARITY_DESC') 'SEARCH_MATCH' else sort],
      'free': ?sourceIds,
      'ids': ?onlyIds,
      'page': page,
    });
    return PageResult(_media(data, 'Page'), data['Page']['pageInfo']['hasNextPage'] == true);
  }

  static Future<Media> detail(int id) async {
    final data = await _ask(_detail, {'id': id});
    return Media.fromJson(data['Media']);
  }
}

const genreChoices = ['Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy', 'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery', 'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller'];
