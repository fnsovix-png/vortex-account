class Track {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final int? duration;
  final String thumbnail;
  final String? artistId;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    required this.thumbnail,
    this.artistId,
  });

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'],
        title: j['title'] ?? 'Unknown',
        artist: j['artist'] ?? '',
        album: j['album'],
        duration: (j['duration'] as num?)?.toInt(),
        thumbnail: j['thumbnail'] ?? '',
        artistId: j['artist_id'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
        'thumbnail': thumbnail,
        'artist_id': artistId,
      };

  String get artUrl {
    if (thumbnail.contains('googleusercontent.com') || thumbnail.contains('ggpht.com')) {
      return thumbnail.replaceAll(RegExp(r'=w\d+-h\d+.*$'), '=w544-h544-l90-rj');
    }
    return thumbnail;
  }
}

class Playlist {
  final String id;
  final String name;
  final int? cover;
  final List<Track> tracks;

  const Playlist(this.id, this.name, this.cover, this.tracks);

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        j['id'],
        j['name'] ?? 'Playlist',
        (j['cover'] as num?)?.toInt(),
        ((j['tracks'] ?? const []) as List).map((e) => Track.fromJson(e)).toList(),
      );
}

class UpdatePackage {
  final String file;
  final String sha256;
  final int size;

  const UpdatePackage(this.file, this.sha256, this.size);

  static UpdatePackage? fromJson(dynamic j) => j == null ? null : UpdatePackage(j['file'], j['sha256'], (j['size'] as num?)?.toInt() ?? 0);
}

class ReleaseNote {
  final String version;
  final String date;
  final List<String> changes;

  const ReleaseNote(this.version, this.date, this.changes);
}

class ReleaseInfo {
  final String version;
  final List<ReleaseNote> notes;
  final UpdatePackage? android;
  final UpdatePackage? windows;

  const ReleaseInfo(this.version, this.notes, this.android, this.windows);

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) => ReleaseInfo(
        j['version'] ?? '0.0.0',
        [
          for (final n in (j['notes'] ?? const []) as List)
            ReleaseNote(n['version'] ?? '', n['date'] ?? '', [for (final c in (n['changes'] ?? const []) as List) '$c']),
        ],
        UpdatePackage.fromJson(j['android']),
        UpdatePackage.fromJson(j['windows']),
      );
}

bool isNewerVersion(String candidate, String current) {
  List<int> parts(String v) => v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final a = parts(candidate), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

class ArtistCard {
  final String id;
  final String name;
  final String thumbnail;

  const ArtistCard(this.id, this.name, this.thumbnail);

  factory ArtistCard.fromJson(Map<String, dynamic> j) => ArtistCard(j['id'], j['name'] ?? 'Unknown', j['thumbnail'] ?? '');
}

class AlbumCard {
  final String id;
  final String title;
  final String artist;
  final String? year;
  final String thumbnail;

  const AlbumCard(this.id, this.title, this.artist, this.year, this.thumbnail);

  factory AlbumCard.fromJson(Map<String, dynamic> j) => AlbumCard(j['id'], j['title'] ?? 'Unknown', j['artist'] ?? '', j['year']?.toString(), j['thumbnail'] ?? '');
}

class ArtistPage {
  final String name;
  final String? description;
  final String thumbnail;
  final List<Track> songs;
  final List<AlbumCard> albums;

  const ArtistPage(this.name, this.description, this.thumbnail, this.songs, this.albums);

  factory ArtistPage.fromJson(Map<String, dynamic> j) => ArtistPage(
        j['name'] ?? 'Unknown',
        j['description'],
        j['thumbnail'] ?? '',
        (j['songs'] as List).map((e) => Track.fromJson(e)).toList(),
        (j['albums'] as List).map((e) => AlbumCard.fromJson(e)).toList(),
      );
}

class AlbumPage {
  final String title;
  final String artist;
  final String? artistId;
  final String? year;
  final String thumbnail;
  final List<Track> tracks;

  const AlbumPage(this.title, this.artist, this.artistId, this.year, this.thumbnail, this.tracks);

  factory AlbumPage.fromJson(Map<String, dynamic> j) => AlbumPage(
        j['title'] ?? 'Unknown',
        j['artist'] ?? '',
        j['artist_id'],
        j['year']?.toString(),
        j['thumbnail'] ?? '',
        (j['tracks'] as List).map((e) => Track.fromJson(e)).toList(),
      );
}

Map<String, int> _imageVersions(dynamic raw) => {for (final e in ((raw ?? {}) as Map).entries) '${e.key}': (e.value as num).toInt()};

class Profile {
  final int id;
  final String username;
  final String email;
  final String theme;
  final int plays;
  final int listeningSeconds;
  final Map<String, int> images;
  final String pronouns;
  final String bio;
  final String quote;
  final String status;
  final int streak;
  final int bestStreak;
  final bool crown;

  const Profile({
    required this.id,
    required this.username,
    required this.email,
    required this.theme,
    required this.plays,
    required this.listeningSeconds,
    required this.images,
    this.pronouns = '',
    this.bio = '',
    this.quote = '',
    this.status = 'online',
    this.streak = 0,
    this.bestStreak = 0,
    this.crown = false,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: (j['id'] as num).toInt(),
        username: j['username'] ?? '',
        email: j['email'] ?? '',
        theme: j['theme'] ?? 'auto',
        plays: (j['plays'] as num?)?.toInt() ?? 0,
        listeningSeconds: (j['listening_seconds'] as num?)?.toInt() ?? 0,
        images: _imageVersions(j['images']),
        pronouns: j['pronouns'] ?? '',
        bio: j['bio'] ?? '',
        quote: j['quote'] ?? '',
        status: j['status'] ?? 'online',
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        bestStreak: (j['best_streak'] as num?)?.toInt() ?? 0,
        crown: j['crown'] == true,
      );
}

class Person {
  final int id;
  final String username;
  final String friendship;
  final Map<String, int> images;
  final bool online;
  final bool isPlaying;
  final Track? nowPlaying;
  final int listeningSeconds;
  final int plays;
  final int unread;
  final List<TopArtist> topArtists;
  final String pronouns;
  final String bio;
  final String quote;
  final String status;
  final int joined;
  final int streak;
  final int bestStreak;
  final bool crown;

  const Person({
    required this.id,
    required this.username,
    required this.friendship,
    required this.images,
    required this.online,
    required this.isPlaying,
    required this.nowPlaying,
    required this.listeningSeconds,
    required this.plays,
    required this.unread,
    required this.topArtists,
    this.pronouns = '',
    this.bio = '',
    this.quote = '',
    this.status = '',
    this.joined = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.crown = false,
  });

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: (j['id'] as num).toInt(),
        username: j['username'] ?? '?',
        friendship: j['friendship'] ?? 'none',
        images: _imageVersions(j['images']),
        online: j['online'] ?? false,
        isPlaying: j['is_playing'] ?? false,
        nowPlaying: j['now_playing'] == null ? null : Track.fromJson(j['now_playing']),
        listeningSeconds: (j['listening_seconds'] as num?)?.toInt() ?? 0,
        plays: (j['plays'] as num?)?.toInt() ?? 0,
        unread: (j['unread'] as num?)?.toInt() ?? 0,
        topArtists: [for (final a in (j['top_artists'] ?? const []) as List) TopArtist(a['name'], a['thumbnail'] ?? '')],
        pronouns: j['pronouns'] ?? '',
        bio: j['bio'] ?? '',
        quote: j['quote'] ?? '',
        status: j['status'] ?? '',
        joined: (j['joined'] as num?)?.toInt() ?? 0,
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        bestStreak: (j['best_streak'] as num?)?.toInt() ?? 0,
        crown: j['crown'] == true,
      );
}

class ChatMessage {
  final int id;
  final int senderId;
  final String body;
  final Track? track;
  final bool gift;

  const ChatMessage(this.id, this.senderId, this.body, this.track, {this.gift = false});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        (j['id'] as num).toInt(),
        (j['sender_id'] as num).toInt(),
        j['body'] ?? '',
        j['track'] == null ? null : Track.fromJson(j['track']),
        gift: j['track'] is Map && j['track']['gift'] == true,
      );
}

class RecommendationShelf {
  final String title;
  final List<Track> tracks;

  const RecommendationShelf(this.title, this.tracks);
}

class TopArtist {
  final String name;
  final String thumbnail;

  const TopArtist(this.name, this.thumbnail);
}

class LyricLine {
  final Duration time;
  final String text;

  const LyricLine(this.time, this.text);

  bool get isBreak => text.isEmpty;
}

class Lyrics {
  final List<LyricLine> synced;
  final List<String> plain;

  const Lyrics(this.synced, this.plain);

  bool get isEmpty => synced.isEmpty && plain.isEmpty;

  static final _stamp = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');

  factory Lyrics.parse(String? synced, String? plain) {
    final lines = <LyricLine>[];
    for (final raw in (synced ?? '').split('\n')) {
      final matches = _stamp.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.substring(matches.last.end).trim();
      for (final m in matches) {
        final fraction = (m.group(3) ?? '0').padRight(3, '0').substring(0, 3);
        lines.add(LyricLine(
          Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: int.parse(fraction)),
          text,
        ));
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    final plainLines = (plain ?? '').split('\n').map((l) => l.trim()).toList();
    while (plainLines.isNotEmpty && plainLines.last.isEmpty) {
      plainLines.removeLast();
    }
    return Lyrics(lines, plainLines);
  }
}

String formatDuration(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
