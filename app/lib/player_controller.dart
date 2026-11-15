import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'appearance.dart';
import 'fx.dart';
import 'models.dart';
import 'server_launcher.dart';
import 'theme.dart';

enum RepeatSetting { off, all, one }

class PlayerController extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();
  final Api api;
  final SharedPreferences prefs;
  final ValueNotifier<Color> tint = ValueNotifier(defaultTint);
  final ValueNotifier<List<Color>> palette = ValueNotifier(defaultPalette);

  List<Track> _queue = [];
  List<Track> _ordered = [];
  int _index = -1;
  bool shuffle = false;
  RepeatSetting repeat = RepeatSetting.off;
  double speed = 1;
  String? error;
  List<Track> liked = [];
  List<Track> recent = [];
  DateTime? sleepAt;
  Profile? profile;
  bool profileLoaded = false;
  List<RecommendationShelf> shelves = [];
  List<TopArtist> topArtists = [];
  final ValueNotifier<String?> searchRequest = ValueNotifier(null);

  final ValueNotifier<int> appearanceVersion = ValueNotifier(0);
  List<Playlist> playlists = [];
  List<Person> friends = [];
  List<Person> incomingRequests = [];
  List<Person> outgoingRequests = [];
  Timer? _heartbeat;
  DateTime _lastBeat = DateTime.now();
  String _lastFriendsSignature = '';
  final Completer<void> introDone = Completer<void>();
  bool _appVisible = true;
  late final AppLifecycleListener _lifecycle;
  String fontId = 'system';
  double cardSize = 160;
  ProcessingState? _lastProcessing;
  int _paletteId = 0;
  DateTime? _lastRecommendations;

  int _loadId = 0;
  int _readyLoadId = -1;
  int _completedLoadId = -1;
  Timer? _sleepTimer;
  StreamSubscription<PlayerState>? _stateSub;

  PlayerController(this.api, this.prefs) {
    api.key = prefs.getString('key') ?? api.key;
    final savedServer = prefs.getString('server');
    // Old builds saved the Fly address, which is switched off now: fall back to the built-in one.
    final stale = savedServer != null && savedServer.contains('fly.dev');
    if (stale) {
      prefs.remove('server');
      api.key = '';
    } else if (savedServer != null && savedServer.isNotEmpty) {
      api.server = savedServer;
    }
    liked = _load('liked');
    recent = _load('recent');
    shuffle = prefs.getBool('shuffle') ?? false;
    repeat = RepeatSetting.values[(prefs.getInt('repeat') ?? 0).clamp(0, RepeatSetting.values.length - 1)];
    fontId = prefs.getString('font') ?? 'system';
    cardSize = prefs.getDouble('cardSize') ?? 160;
    VortexStyles.current = VortexStyles.byId(prefs.getString('style'));
    AppColors.accent = VortexStyles.current.accent;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => _appVisible = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
    );
    _applyLoopMode();
    applyPalette();
    _stateSub = player.playerStateStream.listen((s) {
      final finishedNow = s.processingState == ProcessingState.completed && _lastProcessing != ProcessingState.completed;
      _lastProcessing = s.processingState;
      if (finishedNow && _readyLoadId == _loadId && _completedLoadId != _loadId) {
        _completedLoadId = _loadId;
        _onComplete();
      }
    });
  }

  VortexStyle get style => VortexStyles.current;
  bool _option(String key) => prefs.getBool(key) ?? true;
  bool get decorations => _option('decorations');
  bool get animatedBackground => _option('animatedBackground');
  bool get showRing => _option('showRing');
  bool get showWave => _option('showWave');
  bool get autoplay => _option('autoplay');

  void setOption(String key, bool value) {
    prefs.setBool(key, value);
    notifyListeners();
  }


  void setCardSize(double size) {
    cardSize = size;
    prefs.setDouble('cardSize', size);
    notifyListeners();
  }

  void setStyle(String id) {
    VortexStyles.current = VortexStyles.byId(id);
    prefs.setString('style', id);
    applyPalette();
  }

  void setFont(String id) {
    fontId = id;
    prefs.setString('font', id);
    appearanceVersion.value++;
    notifyListeners();
  }

  void _applyLoopMode() {
    player.setLoopMode(repeat == RepeatSetting.one ? LoopMode.one : LoopMode.off);
  }

  void togglePlay() {
    if (current == null) return;
    player.playing ? player.pause() : player.play();
  }

  void seekBy(Duration delta) {
    if (current == null) return;
    final target = player.position + delta;
    player.seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> shufflePlay(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (!shuffle) toggleShuffle();
    await playList(tracks, Random().nextInt(tracks.length));
  }

  Future<bool> _extendWithRadio() async {
    final t = current;
    if (t == null) return false;
    try {
      final existing = _queue.map((q) => q.id).toSet();
      final more = (await api.radio(t.id)).where((r) => !existing.contains(r.id)).toList();
      if (more.isEmpty) return false;
      _queue.addAll(more);
      _ordered.addAll(more);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Color _accentFrom(List<Color> colors) {
    final hsl = HSLColor.fromColor(colors.first);
    if (hsl.saturation < 0.12) return const Color(0xFFF0F0F4);
    return hsl.withLightness(0.74).withSaturation(hsl.saturation.clamp(0.6, 1.0)).toColor();
  }

  List<Track> _load(String key) {
    final raw = prefs.getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Track.fromJson(e)).toList();
  }

  void _save(String key, List<Track> list) => prefs.setString(key, jsonEncode(list.map((t) => t.toJson()).toList()));

  List<Track> get queue => _queue;
  int get index => _index;
  Track? get current => _index >= 0 && _index < _queue.length ? _queue[_index] : null;
  bool get hasNext => _queue.isNotEmpty && (repeat != RepeatSetting.off || autoplay || _index + 1 < _queue.length);
  bool get needsServer => api.server.isEmpty;

  String get repeatLabel => switch (repeat) {
        RepeatSetting.off => 'Loop off',
        RepeatSetting.all => 'Looping queue',
        RepeatSetting.one => 'Looping this song',
      };

  bool isLiked(Track t) => liked.any((l) => l.id == t.id);

  void toggleLike(Track t) {
    if (isLiked(t)) {
      liked.removeWhere((l) => l.id == t.id);
    } else {
      liked.insert(0, t);
    }
    _save('liked', liked);
    notifyListeners();
    api.saveLiked(liked).catchError((_) {});
  }

  void _replacePlaylist(Playlist updated) {
    final i = playlists.indexWhere((p) => p.id == updated.id);
    if (i >= 0) playlists[i] = updated;
    notifyListeners();
  }

  Future<void> refreshPlaylists() async {
    try {
      playlists = await api.playlists();
      notifyListeners();
    } catch (_) {}
  }

  Future<Playlist> createPlaylist(String name) async {
    final created = await api.createPlaylist(name);
    playlists.insert(0, created);
    notifyListeners();
    return created;
  }

  Future<void> renamePlaylist(String id, String name) async => _replacePlaylist(await api.renamePlaylist(id, name));

  Future<void> deletePlaylist(String id) async {
    await api.deletePlaylist(id);
    playlists.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> addToPlaylist(String id, Track t) async => _replacePlaylist(await api.addPlaylistTrack(id, t));

  Future<void> removeFromPlaylist(String id, String trackId) async => _replacePlaylist(await api.removePlaylistTrack(id, trackId));

  Future<void> setPlaylistCover(String id, List<int> bytes) async => _replacePlaylist(await api.setPlaylistCover(id, bytes));

  Future<void> removePlaylistCover(String id) async => _replacePlaylist(await api.removePlaylistCover(id));

  Future<void> prepareServer() async {
    if (api.server.contains('127.0.0.1')) await ensureServer();
  }

  bool get signedIn => api.key.isNotEmpty;

  void useServer(String server) {
    api.server = server;
    prefs.setString('server', server);
  }

  void setServer(String server) {
    useServer(server);
    _clearSession();
  }

  Future<void> _startSession(String token) async {
    api.key = token;
    await prefs.setString('key', token);
    notifyListeners();
    await loadProfile();
  }

  Future<void> signIn(String email, String password) async {
    if (api.server.contains('127.0.0.1')) await ensureServer();
    await _startSession(await api.login(email, password));
  }

  Future<void> register(String email, String password, String username) async {
    if (api.server.contains('127.0.0.1')) await ensureServer();
    await _startSession(await api.register(email, password, username));
  }

  Future<void> signOut() async {
    try {
      await api.logout();
    } catch (_) {}
    _clearSession();
  }

  Future<void> deleteAccount() async {
    await api.deleteAccount();
    _clearSession();
  }

  void _clearSession() {
    api.key = '';
    prefs.remove('key');
    prefs.remove('liked');
    prefs.remove('recent');
    player.stop();
    _heartbeat?.cancel();
    _heartbeat = null;
    _queue = [];
    _ordered = [];
    _index = -1;
    liked = [];
    recent = [];
    shelves = [];
    topArtists = [];
    playlists = [];
    friends = [];
    incomingRequests = [];
    outgoingRequests = [];
    profile = null;
    profileLoaded = false;
    applyPalette();
    notifyListeners();
  }

  int get unreadCount {
    if (profile?.status == 'dnd' || profile?.status == 'sleep') return 0;
    return friends.fold(0, (sum, f) => sum + f.unread) + incomingRequests.length;
  }

  Future<void> refreshFriends() async {
    if (!signedIn) return;
    try {
      final data = await api.friends();
      final signature = _friendsSignature(data);
      if (signature == _lastFriendsSignature) return;
      _lastFriendsSignature = signature;
      friends = data['friends']!..sort((a, b) => (b.online ? 1 : 0) - (a.online ? 1 : 0));
      incomingRequests = data['incoming']!;
      outgoingRequests = data['outgoing']!;
      notifyListeners();
    } on SignedOut {
      _clearSession();
    } catch (_) {}
  }

  String _friendsSignature(Map<String, List<Person>> data) {
    return [
      for (final entry in data.entries)
        for (final p in entry.value)
          '${entry.key},${p.id},${p.username},${p.online},${p.isPlaying},${p.nowPlaying?.id},${p.unread},${p.status},${p.streak},${p.images}',
    ].join('|');
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _lastBeat = DateTime.now();
    _beat();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => _beat());
  }

  Future<void> _beat() async {
    if (!signedIn) return;
    final now = DateTime.now();
    final seconds = now.difference(_lastBeat).inSeconds.clamp(0, 60);
    _lastBeat = now;
    final playing = current != null && player.playing;
    if (!playing && !_appVisible) return;
    try {
      await api.presence(current, playing, playing ? seconds : 0);
    } catch (_) {}
    await refreshFriends();
  }

  Future<void> playList(List<Track> tracks, int start) async {
    _ordered = List.of(tracks);
    if (shuffle) {
      final first = tracks[start];
      final rest = List.of(tracks)..removeAt(start);
      rest.shuffle();
      _queue = [first, ...rest];
      _index = 0;
    } else {
      _queue = List.of(tracks);
      _index = start;
    }
    await _loadCurrent();
  }

  void playNext(Track t) {
    if (current == null) {
      playList([t], 0);
      return;
    }
    _queue.insert(_index + 1, t);
    final orderedIndex = _ordered.indexWhere((o) => o.id == current!.id);
    _ordered.insert(orderedIndex + 1, t);
    _prefetchNext();
    notifyListeners();
  }

  void addToQueue(Track t) {
    if (current == null) {
      playList([t], 0);
      return;
    }
    _queue.add(t);
    _ordered.add(t);
    notifyListeners();
  }

  Future<void> jumpTo(int i) async {
    _index = i;
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final t = current;
    if (t == null) return;
    final load = ++_loadId;
    error = null;
    recent.removeWhere((r) => r.id == t.id);
    recent.insert(0, t);
    if (recent.length > 30) recent = recent.sublist(0, 30);
    _save('recent', recent);
    notifyListeners();
    applyPalette();
    try {
      await player.stop();
      if (load != _loadId) return;
      await player.setAudioSource(AudioSource.uri(Uri.parse(api.streamUrl(t.id))));
      if (load != _loadId) return;
      _readyLoadId = load;
      player.play();
      _prefetchNext();
      _logPlay(t);
    } catch (e) {
      if (load != _loadId) return;
      error = 'This song can\'t play right now. Try another one.';
      notifyListeners();
    }
  }

  String? get wallpaperUrl => imageUrl('wallpaper');

  String? imageUrl(String kind) {
    final version = profile?.images[kind];
    return version == null ? null : api.imageUrl(kind, version);
  }

  Future<void> applyPalette() async {
    final id = ++_paletteId;
    final wallpaper = wallpaperUrl;
    final preset = themePresets.where((p) => p.id == profile?.theme).firstOrNull;
    final track = current;
    try {
      final styled = style.palette.isNotEmpty ? style.palette : null;
      final colors = wallpaper != null
          ? await paletteFromUrl(wallpaper)
          : preset?.colors ?? styled ?? (track != null ? await coverPalette(track.thumbnail) : defaultPalette);
      if (id != _paletteId) return;
      palette.value = colors;
      tint.value = colors.first;
      AppColors.accent = wallpaper != null || preset != null ? _accentFrom(colors) : style.accent;
      appearanceVersion.value++;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadProfile() async {
    if (needsServer || !signedIn) return;
    if (api.server.contains('127.0.0.1')) await ensureServer();
    try {
      _setProfile(await api.profile());
      refreshRecommendations(force: true);
      _syncLiked();
      refreshPlaylists();
      _startHeartbeat();
    } on SignedOut {
      _clearSession();
    } catch (_) {
      profileLoaded = false;
      notifyListeners();
    }
  }

  Future<void> _syncLiked() async {
    try {
      final server = await api.likedSongs();
      final ids = liked.map((l) => l.id).toSet();
      final merged = [...liked, ...server.where((s) => !ids.contains(s.id))];
      if (merged.length != liked.length) {
        liked = merged;
        _save('liked', liked);
        notifyListeners();
      }
      if (merged.length != server.length) await api.saveLiked(liked);
    } catch (_) {}
  }

  void _setProfile(Profile value) {
    profile = value;
    profileLoaded = true;
    applyPalette();
    notifyListeners();
  }

  Future<void> saveProfile({String? username, String? theme, String? pronouns, String? bio, String? quote, String? status}) async {
    _setProfile(await api.updateProfile(username: username, theme: theme, pronouns: pronouns, bio: bio, quote: quote, status: status));
  }

  Future<void> setProfileImage(String kind, List<int> bytes) async {
    _setProfile(await api.uploadImage(kind, bytes));
  }

  Future<void> removeProfileImage(String kind) async {
    _setProfile(await api.deleteImage(kind));
  }

  Future<void> clearHistory() async {
    await api.clearHistory();
    shelves = [];
    topArtists = [];
    _setProfile(await api.profile());
  }

  void requestSearch(String query) => searchRequest.value = query;

  Future<void> refreshRecommendations({bool force = false}) async {
    final now = DateTime.now();
    final last = _lastRecommendations;
    if (!force && last != null && now.difference(last) < const Duration(minutes: 1)) return;
    _lastRecommendations = now;
    try {
      final (newShelves, artists) = await api.recommendations();
      shelves = newShelves;
      topArtists = artists;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _logPlay(Track t) async {
    try {
      final streak = await api.logPlay(t);
      if (streak != null && streak != profile?.streak) _setProfile(await api.profile());
      refreshRecommendations();
    } catch (_) {}
  }

  void _prefetchNext() {
    if (!hasNext) return;
    if (_index + 1 < _queue.length) {
      api.prefetch(_queue[_index + 1].id);
    } else if (repeat != RepeatSetting.off && _queue.length > 1) {
      api.prefetch(_queue.first.id);
    }
  }

  Future<void> _onComplete() async {
    if (repeat == RepeatSetting.one) {
      await player.seek(Duration.zero);
      _completedLoadId = -1;
      player.play();
      return;
    }
    if (hasNext && await _advance()) return;
    await player.pause();
    await player.seek(Duration.zero);
    _completedLoadId = -1;
  }

  Future<void> next() async {
    await _advance();
  }

  Future<bool> _advance() async {
    if (_queue.isEmpty) return false;
    if (_index + 1 >= _queue.length && repeat == RepeatSetting.off) {
      if (!autoplay || !await _extendWithRadio()) return false;
    }
    _index = _index + 1 < _queue.length ? _index + 1 : 0;
    await _loadCurrent();
    return true;
  }

  void previous() {
    if (_index > 0) {
      _index--;
    } else if (repeat != RepeatSetting.off && _queue.length > 1) {
      _index = _queue.length - 1;
    } else {
      player.seek(Duration.zero);
      return;
    }
    _loadCurrent();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    prefs.setBool('shuffle', shuffle);
    final cur = current;
    if (cur != null && _queue.length > 1) {
      if (shuffle) {
        final rest = List.of(_queue)..removeAt(_index);
        rest.shuffle();
        _queue = [cur, ...rest];
        _index = 0;
      } else {
        _queue = List.of(_ordered);
        _index = _queue.indexWhere((t) => t.id == cur.id);
      }
      _prefetchNext();
    }
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = RepeatSetting.values[(repeat.index + 1) % RepeatSetting.values.length];
    prefs.setInt('repeat', repeat.index);
    _applyLoopMode();
    notifyListeners();
  }

  void setSpeed(double value) {
    speed = value;
    player.setSpeed(value);
    notifyListeners();
  }

  void setSleepTimer(Duration? after) {
    _sleepTimer?.cancel();
    sleepAt = after == null ? null : DateTime.now().add(after);
    if (after != null) {
      _sleepTimer = Timer(after, () {
        player.pause();
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _heartbeat?.cancel();
    _stateSub?.cancel();
    _lifecycle.dispose();
    tint.dispose();
    palette.dispose();
    appearanceVersion.dispose();
    searchRequest.dispose();
    player.dispose();
    super.dispose();
  }
}
