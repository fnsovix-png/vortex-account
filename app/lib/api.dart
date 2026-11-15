import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class Pairing {
  final String url;

  const Pairing(this.url);
}

class SignedOut implements Exception {
  const SignedOut();
}

class Api {
  static late Api instance;

  String server;
  String key;
  final Map<String, Lyrics> _lyricsCache = {};

  Api(this.server, {this.key = ''}) {
    instance = this;
  }

  Map<String, String> get _auth => key.isEmpty ? const {} : {'key': key};

  Future<List<Track>> search(String q, {int limit = 25}) async {
    final uri = Uri.parse('$server/search').replace(queryParameters: {'q': q, 'limit': '$limit', ..._auth});
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) throw const SignedOut();
    if (res.statusCode != 200) throw 'Something went wrong. Try again.';
    return (jsonDecode(utf8.decode(res.bodyBytes)) as List).map((e) => Track.fromJson(e)).toList();
  }

  Future<Lyrics> lyrics(Track t) async {
    final cached = _lyricsCache[t.id];
    if (cached != null) return cached;
    final uri = Uri.parse('$server/lyrics').replace(queryParameters: {
      'title': t.title,
      'artist': t.artist,
      if (t.album != null) 'album': t.album!,
      if (t.duration != null) 'duration': '${t.duration}',
      ..._auth,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw 'Something went wrong. Try again.';
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final lyrics = Lyrics.parse(j['synced'], j['plain']);
    _lyricsCache[t.id] = lyrics;
    return lyrics;
  }

  String _detail(http.Response res) {
    try {
      final detail = jsonDecode(utf8.decode(res.bodyBytes))['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty && detail.first['msg'] is String) return detail.first['msg'];
    } catch (_) {}
    return 'Please check what you entered and try again.';
  }

  Future<String> _auth2(String path, Map<String, String> body) async {
    http.Response? reply;
    for (var attempt = 0; attempt < 3 && reply == null; attempt++) {
      try {
        reply = await http.post(Uri.parse('$server$path'), headers: const {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 25));
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    final res = reply;
    if (res == null) throw 'Check your internet connection and try again.';
    if (res.statusCode != 200) throw _detail(res);
    return jsonDecode(res.body)['token'];
  }

  Future<String> register(String email, String password, String username) =>
      _auth2('/auth/register', {'email': email, 'password': password, 'username': username});

  Future<String> login(String email, String password) => _auth2('/auth/login', {'email': email, 'password': password});

  Future<void> logout() async {
    await http.post(_uri('/auth/logout')).timeout(const Duration(seconds: 8));
  }

  Future<void> changePassword(String current, String next) async {
    final res = await http.post(_uri('/auth/password'), headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'current': current, 'new': next})).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw _detail(res);
  }

  Future<void> deleteAccount() async {
    final res = await http.delete(_uri('/account')).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw _detail(res);
  }

  Future<void> presence(Track? track, bool playing, int seconds) async {
    await http.post(_uri('/presence'), headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'track': track?.toJson(), 'playing': playing, 'seconds': seconds})).timeout(const Duration(seconds: 10));
  }

  Future<List<Person>> searchPeople(String q) async => ((await _getJson('/people/search', {'q': q})) as List).map((e) => Person.fromJson(e)).toList();

  Future<Person> person(int id) async => Person.fromJson(await _getJson('/people/$id'));

  String personImageUrl(int id, String kind, int version) => _uri('/people/$id/image/$kind', {'v': '$version'}).toString();

  Future<Map<String, List<Person>>> friends() async {
    final j = await _getJson('/friends');
    return {for (final k in const ['friends', 'incoming', 'outgoing']) k: (j[k] as List).map((e) => Person.fromJson(e)).toList()};
  }

  Future<void> addFriend(int id) async {
    final res = await http.post(_uri('/friends/$id')).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw _detail(res);
  }

  Future<void> removeFriend(int id) async {
    await http.delete(_uri('/friends/$id')).timeout(const Duration(seconds: 10));
  }

  Future<List<ChatMessage>> messages(int id, int after) async => ((await _getJson('/messages/$id', {'after': '$after'})) as List).map((e) => ChatMessage.fromJson(e)).toList();

  final http.Client _chatClient = http.Client();

  /// Held open by the server until a message arrives (or ~25 s pass), so new
  /// messages show up immediately. Throws [UnsupportedError] on servers without it.
  Future<List<ChatMessage>> waitMessages(int id, int after) async {
    final res = await _chatClient.get(_uri('/messages/$id/wait', {'after': '$after'})).timeout(const Duration(seconds: 40));
    if (res.statusCode == 404 || res.statusCode == 405) throw UnsupportedError('no live chat');
    if (res.statusCode == 401) throw const SignedOut();
    if (res.statusCode != 200) throw _detail(res);
    return (jsonDecode(utf8.decode(res.bodyBytes)) as List).map((e) => ChatMessage.fromJson(e)).toList();
  }

  Future<ChatMessage> sendMessage(int id, String body, {Track? track, bool gift = false}) async {
    final res = await http.post(_uri('/messages/$id'), headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'body': body, 'track': track?.toJson(), if (gift) 'gift': true})).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw _detail(res);
    return ChatMessage.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  Uri _uri(String path, [Map<String, String> query = const {}]) {
    final params = {...query, ..._auth};
    return Uri.parse('$server$path').replace(queryParameters: params.isEmpty ? null : params);
  }

  Profile _profileFrom(http.Response res) {
    if (res.statusCode == 401) throw const SignedOut();
    if (res.statusCode == 409) throw _detail(res);
    if (res.statusCode == 400) throw _detail(res);
    if (res.statusCode == 413) throw 'That image is larger than 10 MB.';
    if (res.statusCode == 415) throw 'Use a PNG, JPEG, WebP or GIF image.';
    if (res.statusCode != 200) throw 'Something went wrong. Try again.';
    return Profile.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  Future<Profile> profile() async => _profileFrom(await http.get(_uri('/profile')).timeout(const Duration(seconds: 10)));

  Future<Profile> updateProfile({String? username, String? theme, String? pronouns, String? bio, String? quote, String? status}) async {
    final body = jsonEncode({'username': ?username, 'theme': ?theme, 'pronouns': ?pronouns, 'bio': ?bio, 'quote': ?quote, 'status': ?status});
    return _profileFrom(await http.post(_uri('/profile'), headers: const {'Content-Type': 'application/json'}, body: body).timeout(const Duration(seconds: 10)));
  }

  Future<Profile> uploadImage(String kind, List<int> bytes) async {
    return _profileFrom(await http.put(_uri('/profile/image/$kind'), body: bytes).timeout(const Duration(seconds: 60)));
  }

  Future<Profile> deleteImage(String kind) async => _profileFrom(await http.delete(_uri('/profile/image/$kind')).timeout(const Duration(seconds: 10)));

  String imageUrl(String kind, int version) => _uri('/profile/image/$kind', {'v': '$version'}).toString();

  Future<int?> logPlay(Track t) async {
    final uri = _uri('/history', {'tz': '${DateTime.now().timeZoneOffset.inMinutes}'});
    final res = await http.post(uri, headers: const {'Content-Type': 'application/json'}, body: jsonEncode(t.toJson())).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return (jsonDecode(res.body)['streak'] as num?)?.toInt();
  }

  Future<void> clearHistory() async {
    await http.delete(_uri('/history')).timeout(const Duration(seconds: 10));
  }

  Future<List<String>> suggest(String q) async {
    final res = await http.get(_uri('/suggest', {'q': q})).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return const [];
    return (jsonDecode(utf8.decode(res.bodyBytes)) as List).map((e) => '$e').toList();
  }

  Future<(List<RecommendationShelf>, List<TopArtist>)> recommendations() async {
    final res = await http.get(_uri('/recommendations')).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw 'Something went wrong. Try again.';
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final shelves = [
      for (final s in j['shelves']) RecommendationShelf(s['title'], (s['tracks'] as List).map((e) => Track.fromJson(e)).toList()),
    ];
    final artists = [for (final a in j['top_artists']) TopArtist(a['name'], a['thumbnail'] ?? '')];
    return (shelves, artists);
  }

  Future<dynamic> _getJson(String path, [Map<String, String> query = const {}]) async {
    final res = await http.get(_uri(path, query)).timeout(const Duration(seconds: 45));
    if (res.statusCode == 401) throw const SignedOut();
    if (res.statusCode != 200) throw 'Something went wrong. Try again.';
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<(List<ArtistCard>, List<AlbumCard>)> browseSearch(String q) async {
    final j = await _getJson('/browse/search', {'q': q});
    return (
      (j['artists'] as List).map((e) => ArtistCard.fromJson(e)).toList(),
      (j['albums'] as List).map((e) => AlbumCard.fromJson(e)).toList(),
    );
  }

  Future<ArtistPage> artist(String id) async => ArtistPage.fromJson(await _getJson('/artist/$id'));

  Future<AlbumPage> album(String id) async => AlbumPage.fromJson(await _getJson('/album/$id'));

  Future<List<Track>> radio(String id) async => ((await _getJson('/radio/$id')) as List).map((e) => Track.fromJson(e)).toList();

  Future<List<Track>> likedSongs() async => ((await _getJson('/liked')) as List).map((e) => Track.fromJson(e)).toList();

  Future<void> saveLiked(List<Track> tracks) async {
    await http.put(_uri('/liked'), headers: const {'Content-Type': 'application/json'}, body: jsonEncode(tracks.map((t) => t.toJson()).toList())).timeout(const Duration(seconds: 15));
  }

  Future<List<Playlist>> playlists() async => ((await _getJson('/playlists')) as List).map((e) => Playlist.fromJson(e)).toList();

  Playlist _playlistFrom(http.Response res) {
    if (res.statusCode == 413) throw 'That image is larger than 10 MB.';
    if (res.statusCode == 415) throw 'Use a PNG, JPEG, WebP or GIF image.';
    if (res.statusCode != 200) throw _detail(res);
    return Playlist.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  static const _json = {'Content-Type': 'application/json'};
  static const _short = Duration(seconds: 15);

  Future<Playlist> createPlaylist(String name) async => _playlistFrom(await http.post(_uri('/playlists'), headers: _json, body: jsonEncode({'name': name})).timeout(_short));

  Future<Playlist> renamePlaylist(String id, String name) async => _playlistFrom(await http.patch(_uri('/playlists/$id'), headers: _json, body: jsonEncode({'name': name})).timeout(_short));

  Future<void> deletePlaylist(String id) async {
    final res = await http.delete(_uri('/playlists/$id')).timeout(_short);
    if (res.statusCode != 200) throw _detail(res);
  }

  Future<Playlist> addPlaylistTrack(String id, Track t) async => _playlistFrom(await http.post(_uri('/playlists/$id/tracks'), headers: _json, body: jsonEncode(t.toJson())).timeout(_short));

  Future<Playlist> removePlaylistTrack(String id, String trackId) async => _playlistFrom(await http.delete(_uri('/playlists/$id/tracks/$trackId')).timeout(_short));

  Future<Playlist> setPlaylistCover(String id, List<int> bytes) async => _playlistFrom(await http.put(_uri('/playlists/$id/cover'), body: bytes).timeout(const Duration(seconds: 60)));

  Future<Playlist> removePlaylistCover(String id) async => _playlistFrom(await http.delete(_uri('/playlists/$id/cover')).timeout(_short));

  String playlistCoverUrl(String id, int version) => _uri('/playlists/$id/cover', {'v': '$version'}).toString();

  Future<ReleaseInfo?> release() async {
    try {
      final res = await http.get(Uri.parse('$server/release')).timeout(_short);
      if (res.statusCode != 200) return null;
      return ReleaseInfo.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {
      return null;
    }
  }

  String downloadUrl(String file) => '$server/download/$file';

  Future<void> prefetch(String id) async {
    final uri = Uri.parse('$server/prefetch/$id').replace(queryParameters: _auth);
    try {
      await http.get(uri).timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  Future<Pairing?> pairing() async {
    try {
      final res = await http.get(Uri.parse('$server/pairing')).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body);
      return Pairing(j['url']);
    } catch (_) {
      return null;
    }
  }

  String streamUrl(String id) => Uri.parse('$server/stream/$id').replace(queryParameters: _auth.isEmpty ? null : _auth).toString();

  String artUrl(String url) {
    if (url.isEmpty) return url;
    return Uri.parse('$server/art').replace(queryParameters: {'url': url, ..._auth}).toString();
  }
}
