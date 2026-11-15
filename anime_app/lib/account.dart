import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const _hosted = String.fromEnvironment('VORTEX_SERVER', defaultValue: 'https://twilight-meadowland-265.fly.dev');

String get serverUrl => kIsWeb ? Uri.base.origin : _hosted;

class SignedOut implements Exception {
  const SignedOut();
}

/// The same Vortex account, profile, friends and chat as Vortex Music.
class Account extends ChangeNotifier {
  final SharedPreferences prefs;
  String key;
  Me? me;
  Map<int, ListEntry> list = {};
  List<Person> friends = [];
  List<Person> incoming = [];
  List<Person> outgoing = [];
  Timer? _beat;

  Account(this.prefs) : key = prefs.getString('key') ?? '';

  bool get signedIn => key.isNotEmpty;
  int get unread => friends.fold(0, (sum, f) => sum + f.unread) + incoming.length;

  Uri uri(String path, [Map<String, String> query = const {}]) => Uri.parse('$serverUrl$path').replace(queryParameters: {...query, if (key.isNotEmpty) 'key': key});

  String imageUrl(String kind, int version) => uri('/profile/image/$kind', {'v': '$version'}).toString();
  String personImageUrl(int id, String kind, int version) => uri('/people/$id/image/$kind', {'v': '$version'}).toString();

  dynamic _decode(http.Response res) {
    if (res.statusCode == 401) {
      if (signedIn) _clear();
      throw const SignedOut();
    }
    final body = res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      throw detail is String ? detail : 'Something went wrong. Try again.';
    }
    return body;
  }

  static const _json = {'Content-Type': 'application/json'};
  static const _wait = Duration(seconds: 20);

  Future<dynamic> _get(String path, [Map<String, String> query = const {}]) async => _decode(await http.get(uri(path, query)).timeout(_wait));
  Future<dynamic> _post(String path, [Object? body]) async => _decode(await http.post(uri(path), headers: _json, body: jsonEncode(body ?? const {})).timeout(_wait));

  Future<void> _start(String token) async {
    key = token;
    await prefs.setString('key', token);
    await load();
  }

  Future<void> _auth(String path, Map<String, String> body) async {
    final http.Response res;
    try {
      res = await http.post(Uri.parse('$serverUrl$path'), headers: _json, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw 'Check your internet connection and try again.';
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200) throw data is Map && data['detail'] is String ? data['detail'] : 'Something went wrong. Try again.';
    await _start(data['token']);
  }

  Future<void> signIn(String email, String password) => _auth('/auth/login', {'email': email, 'password': password});
  Future<void> register(String email, String password, String username) => _auth('/auth/register', {'email': email, 'password': password, 'username': username});

  Future<void> signOut() async {
    try {
      await http.post(uri('/auth/logout')).timeout(const Duration(seconds: 8));
    } catch (_) {}
    _clear();
  }

  void _clear() {
    key = '';
    prefs.remove('key');
    _beat?.cancel();
    me = null;
    list = {};
    friends = [];
    incoming = [];
    outgoing = [];
    notifyListeners();
  }

  Future<void> load() async {
    if (!signedIn) return;
    try {
      loadVerified().catchError((Object _) {});
      me = Me.fromJson(await _get('/profile'));
      final raw = (await _get('/animelist')) as Map<String, dynamic>;
      list = {for (final e in raw.entries) int.parse(e.key): ListEntry.fromJson(int.parse(e.key), e.value)};
      notifyListeners();
      await refreshFriends();
      _beat?.cancel();
      _beat = Timer.periodic(const Duration(seconds: 25), (_) => _tick());
      _tick();
    } on SignedOut {
      return;
    } catch (_) {
      notifyListeners();
    }
  }

  Future<void> _tick() async {
    if (!signedIn) return;
    try {
      await _post('/presence/ping');
      await refreshFriends();
    } catch (_) {}
  }

  Future<void> refreshFriends() async {
    try {
      final data = await _get('/friends');
      List<Person> people(String k) => [for (final p in data[k] as List) Person.fromJson(p)];
      friends = people('friends')..sort((a, b) => (b.online ? 1 : 0) - (a.online ? 1 : 0));
      incoming = people('incoming');
      outgoing = people('outgoing');
      notifyListeners();
    } catch (_) {}
  }

  // Watchlist

  ListEntry? entry(int id) => list[id];

  Future<void> _store(ListEntry next) async {
    final before = list[next.id];
    list = {...list, next.id: next};
    notifyListeners();
    try {
      await http.put(uri('/animelist/${next.id}'), headers: _json, body: jsonEncode(next.toJson())).timeout(_wait).then(_decode);
    } catch (_) {
      list = {...list};
      if (before == null) {
        list.remove(next.id);
      } else {
        list[next.id] = before;
      }
      notifyListeners();
      rethrow;
    }
  }

  ListEntry _from(Media m) => list[m.id] ?? ListEntry(id: m.id, title: m.title, cover: m.cover, format: m.formatLabel, episodes: m.episodes);

  Future<void> setStatus(Media m, String status) => _store(_from(m).copyWith(status: status));
  Future<void> toggleFavorite(Media m) {
    final current = _from(m);
    return _store(current.copyWith(favorite: !current.favorite));
  }

  Future<void> markWatchedUpTo(Media m, int episode) {
    final total = m.episodes;
    final status = total != null && total > 0 && episode >= total ? 'completed' : 'watching';
    return _store(_from(m).copyWith(progress: episode, status: status));
  }

  Future<void> changeEntry(ListEntry e, {String? status}) => _store(e.copyWith(status: status));

  Future<void> removeEntry(int id) async {
    final before = list[id];
    list = {...list}..remove(id);
    notifyListeners();
    try {
      await http.delete(uri('/animelist/$id')).timeout(_wait).then(_decode);
    } catch (_) {
      if (before != null) list = {...list, id: before};
      notifyListeners();
      rethrow;
    }
  }

  // Sources

  /// Shows whose official playlists were confirmed playing in the Vortex player, by playlist id.
  Map<int, Set<String>> verified = {};
  String verifiedChecked = '';
  Map<int, String> verifiedAudio = {};

  void _readVerified(Map<String, dynamic> j) {
    verifiedChecked = j['checked'] as String? ?? '';
    verified = {for (final e in ((j['shows'] ?? const {}) as Map).entries) int.parse(e.key as String): ((e.value as List).cast<String>()).toSet()};
    verifiedAudio = {for (final e in ((j['audio'] ?? const {}) as Map).entries) int.parse(e.key as String): e.value as String};
  }

  Future<void> loadVerified() async {
    final saved = prefs.getString('verified_sources');
    if (saved != null && verified.isEmpty) _readVerified(jsonDecode(saved));
    final res = await http.get(Uri.parse('$serverUrl/animesources')).timeout(_wait);
    if (res.statusCode != 200) throw 'Check your internet connection and try again.';
    final body = utf8.decode(res.bodyBytes);
    _readVerified(jsonDecode(body));
    await prefs.setString('verified_sources', body);
    notifyListeners();
  }

  /// Clears what this device learned was blocked, so those playlists get another try.
  void forgetBlocks() {
    for (final k in prefs.getKeys().where((k) => k.startsWith('blocked_')).toList()) {
      prefs.remove(k);
    }
    notifyListeners();
  }

  bool playsInVortex(int id) => verified.containsKey(id);

  /// What this show can play from right now, confirmed playlists first.
  List<WatchLink> playable(Media m) {
    final good = verified[m.id] ?? const <String>{};
    final native = m.nativeLinks.where((l) => !isBlocked(l));
    return [...native.where((l) => good.contains(l.youtubePlaylist)), ...native.where((l) => !good.contains(l.youtubePlaylist))];
  }

  // Your place in each episode, and what this device can play.

  double position(int media, int episode) => prefs.getDouble('pos_${media}_$episode') ?? 0;

  void savePosition(int media, int episode, double seconds) {
    prefs.setDouble('pos_${media}_$episode', seconds);
    prefs.setInt('last_ep_$media', episode);
  }

  String? lastSource(int media) => prefs.getString('source_$media');
  void rememberSource(int media, String url) => prefs.setString('source_$media', url);

  bool isBlocked(WatchLink link) {
    final list = link.youtubePlaylist;
    return list != null && (prefs.getBool('blocked_$list') ?? false);
  }

  void markBlocked(WatchLink link) {
    final list = link.youtubePlaylist;
    if (list != null) prefs.setBool('blocked_$list', true);
    notifyListeners();
  }

  // Profile

  Future<void> saveProfile({String? username, String? pronouns, String? bio, String? quote, String? status}) async {
    me = Me.fromJson(await _post('/profile', {'username': ?username, 'pronouns': ?pronouns, 'bio': ?bio, 'quote': ?quote, 'status': ?status}));
    notifyListeners();
  }

  Future<void> uploadImage(String kind, List<int> bytes) async {
    me = Me.fromJson(_decode(await http.put(uri('/profile/image/$kind'), body: bytes).timeout(const Duration(seconds: 60))));
    notifyListeners();
  }

  // People

  Future<List<Person>> searchPeople(String q) async => [for (final p in await _get('/people/search', {'q': q}) as List) Person.fromJson(p)];
  Future<Person> person(int id) async => Person.fromJson(await _get('/people/$id'));

  Future<List<ListEntry>> personList(int id) async {
    final raw = (await _get('/people/$id/animelist')) as Map<String, dynamic>;
    return [for (final e in raw.entries) ListEntry.fromJson(int.parse(e.key), e.value)]..sort((a, b) => b.updated - a.updated);
  }

  Future<void> addFriend(int id) async {
    await _post('/friends/$id');
    await refreshFriends();
  }

  Future<void> removeFriend(int id) async {
    await http.delete(uri('/friends/$id')).timeout(_wait).then(_decode);
    await refreshFriends();
  }

  Future<List<ChatMessage>> messages(int id, int after) async => [for (final m in await _get('/messages/$id', {'after': '$after'}) as List) ChatMessage.fromJson(m)];
  Future<ChatMessage> sendMessage(int id, String body) async => ChatMessage.fromJson(await _post('/messages/$id', {'body': body}));

  Future<Release?> release() async {
    try {
      final res = await http.get(Uri.parse('$serverUrl/release/anime')).timeout(_wait);
      return res.statusCode == 200 ? Release.fromJson(jsonDecode(utf8.decode(res.bodyBytes))) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _beat?.cancel();
    super.dispose();
  }
}
