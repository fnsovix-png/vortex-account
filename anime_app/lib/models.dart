/// Services taken out of Vortex. Their links never appear.
const _removedSites = {'Tubi TV', 'RetroCrush'};
const youtubeSiteIds = [13];

class WatchLink {
  final String site;
  final String url;
  final String type;
  final String? language;
  final String? notes;

  const WatchLink(this.site, this.url, this.type, this.language, [this.notes]);

  factory WatchLink.fromJson(Map<String, dynamic> j) => WatchLink(j['site'] ?? '', j['url'] ?? '', j['type'] ?? '', j['language'], j['notes']);

  bool get isDub => RegExp(r'dub', caseSensitive: false).hasMatch(notes ?? '');
  bool get isSub => RegExp(r'sub', caseSensitive: false).hasMatch(notes ?? '');

  /// Only what AniList actually records, never a guess.
  String get audioLabel {
    final parts = [if (isSub) 'Sub', if (isDub) 'Dub', ?language];
    return parts.isEmpty ? '' : ' · ${parts.join(', ')}';
  }

  /// The playlist id when this link can play inside the app.
  String? get youtubePlaylist {
    if (site != 'YouTube') return null;
    final uri = Uri.tryParse(url);
    final list = uri?.queryParameters['list'];
    return list != null && list.isNotEmpty ? list : null;
  }
}

class StreamEpisode {
  final String title;
  final String thumbnail;
  final String url;
  final String site;

  const StreamEpisode(this.title, this.thumbnail, this.url, this.site);

  factory StreamEpisode.fromJson(Map<String, dynamic> j) => StreamEpisode(j['title'] ?? '', j['thumbnail'] ?? '', j['url'] ?? '', j['site'] ?? '');

  int? get number => int.tryParse(RegExp(r'^Episode\s+(\d+)').firstMatch(title)?.group(1) ?? '');
}

class Media {
  final int id;
  final String title;
  final String? romaji;
  final String? native;
  final String cover;
  final String? banner;
  final String? color;
  final int? year;
  final String? format;
  final int? score;
  final List<String> genres;
  final int? episodes;
  final String? status;
  final String? season;
  final String description;
  final List<WatchLink> links;
  final List<StreamEpisode> streamEpisodes;
  final int? nextEpisode;
  final int? nextAiringAt;
  final List<String> studios;
  final String? trailerYoutube;
  final List<Media> related;
  final List<String> relatedKinds;
  final List<Media> recommended;

  const Media({
    required this.id,
    required this.title,
    this.romaji,
    this.native,
    required this.cover,
    this.banner,
    this.color,
    this.year,
    this.format,
    this.score,
    this.genres = const [],
    this.episodes,
    this.status,
    this.season,
    this.description = '',
    this.links = const [],
    this.streamEpisodes = const [],
    this.nextEpisode,
    this.nextAiringAt,
    this.studios = const [],
    this.trailerYoutube,
    this.related = const [],
    this.relatedKinds = const [],
    this.recommended = const [],
  });

  factory Media.fromJson(Map<String, dynamic> j) {
    final titles = (j['title'] ?? const {}) as Map;
    final cover = (j['coverImage'] ?? const {}) as Map;
    final next = j['nextAiringEpisode'] as Map?;
    final trailer = j['trailer'] as Map?;
    final relations = ((j['relations'] as Map?)?['edges'] ?? const []) as List;
    final recs = ((j['recommendations'] as Map?)?['nodes'] ?? const []) as List;
    final animeRelations = relations.where((e) => e['node']?['type'] == 'ANIME').toList();
    return Media(
      id: j['id'],
      title: titles['english'] ?? titles['romaji'] ?? titles['native'] ?? 'Untitled',
      romaji: titles['romaji'],
      native: titles['native'],
      cover: cover['extraLarge'] ?? cover['large'] ?? '',
      color: cover['color'],
      banner: j['bannerImage'],
      year: j['seasonYear'] ?? (j['startDate'] as Map?)?['year'],
      format: j['format'],
      score: j['averageScore'],
      genres: ((j['genres'] ?? const []) as List).cast<String>(),
      episodes: j['episodes'],
      status: j['status'],
      season: j['season'],
      description: _plainText(j['description']),
      links: [for (final l in (j['externalLinks'] ?? const []) as List) WatchLink.fromJson(l)].where((l) => l.type == 'STREAMING' && !_removedSites.contains(l.site)).toList(),
      streamEpisodes: [for (final e in (j['streamingEpisodes'] ?? const []) as List) StreamEpisode.fromJson(e)],
      nextEpisode: next?['episode'],
      nextAiringAt: next?['airingAt'],
      studios: [for (final s in ((j['studios'] as Map?)?['nodes'] ?? const []) as List) s['name'] as String],
      trailerYoutube: trailer?['site'] == 'youtube' ? trailer!['id'] : null,
      related: [for (final e in animeRelations) Media.fromJson(e['node'])],
      relatedKinds: [for (final e in animeRelations) e['relationType'] as String? ?? ''],
      recommended: [
        for (final r in recs)
          if (r['mediaRecommendation'] != null) Media.fromJson(r['mediaRecommendation']),
      ],
    );
  }

  static String _plainText(String? html) {
    if (html == null) return '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Official sources the Vortex player can run itself.
  List<WatchLink> get nativeLinks => links.where((l) => l.youtubePlaylist != null).toList();

  /// A shared 'known' count, including how far a show still airing has got.
  int? get knownEpisodes {
    if (episodes != null) return episodes;
    if (nextEpisode != null && nextEpisode! > 1) return nextEpisode! - 1;
    final numbers = streamEpisodes.map((e) => e.number).whereType<int>();
    return numbers.isEmpty ? null : numbers.reduce((a, b) => a > b ? a : b);
  }

  String get formatLabel => switch (format) {
        'TV' => 'TV',
        'TV_SHORT' => 'TV Short',
        'MOVIE' => 'Movie',
        'SPECIAL' => 'Special',
        'OVA' => 'OVA',
        'ONA' => 'ONA',
        'MUSIC' => 'Music',
        _ => format ?? '',
      };

  String get statusLabel => switch (status) {
        'RELEASING' => 'Airing',
        'FINISHED' => 'Finished',
        'NOT_YET_RELEASED' => 'Upcoming',
        'CANCELLED' => 'Cancelled',
        'HIATUS' => 'On hiatus',
        _ => '',
      };
}

const listStatuses = {
  'watching': 'Watching',
  'completed': 'Completed',
  'planning': 'Plan to watch',
  'paused': 'On hold',
  'dropped': 'Dropped',
};

class ListEntry {
  final int id;
  final String status;
  final int progress;
  final bool favorite;
  final String title;
  final String cover;
  final String format;
  final int? episodes;
  final int updated;

  const ListEntry({required this.id, this.status = 'planning', this.progress = 0, this.favorite = false, this.title = '', this.cover = '', this.format = '', this.episodes, this.updated = 0});

  factory ListEntry.fromJson(int id, Map<String, dynamic> j) => ListEntry(
        id: id,
        status: j['status'] ?? 'planning',
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        favorite: j['favorite'] ?? false,
        title: j['title'] ?? '',
        cover: j['cover'] ?? '',
        format: j['format'] ?? '',
        episodes: (j['episodes'] as num?)?.toInt(),
        updated: (j['updated'] as num?)?.toInt() ?? 0,
      );

  ListEntry copyWith({String? status, int? progress, bool? favorite}) => ListEntry(
        id: id,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        favorite: favorite ?? this.favorite,
        title: title,
        cover: cover,
        format: format,
        episodes: episodes,
        updated: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

  Map<String, dynamic> toJson() => {'status': status, 'progress': progress, 'favorite': favorite, 'title': title, 'cover': cover, 'format': format, 'episodes': episodes};
}

class Me {
  final int id;
  final String username;
  final String email;
  final String pronouns;
  final String bio;
  final String quote;
  final String status;
  final Map<String, int> images;

  const Me({required this.id, required this.username, required this.email, this.pronouns = '', this.bio = '', this.quote = '', this.status = 'online', this.images = const {}});

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        id: (j['id'] as num).toInt(),
        username: j['username'] ?? '',
        email: j['email'] ?? '',
        pronouns: j['pronouns'] ?? '',
        bio: j['bio'] ?? '',
        quote: j['quote'] ?? '',
        status: j['status'] ?? 'online',
        images: _images(j['images']),
      );
}

Map<String, int> _images(dynamic raw) => {for (final e in ((raw ?? const {}) as Map).entries) e.key as String: (e.value as num).toInt()};

class Person {
  final int id;
  final String username;
  final String friendship;
  final Map<String, int> images;
  final bool online;
  final String status;
  final String pronouns;
  final String bio;
  final String quote;
  final int unread;

  const Person({required this.id, required this.username, required this.friendship, this.images = const {}, this.online = false, this.status = '', this.pronouns = '', this.bio = '', this.quote = '', this.unread = 0});

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: (j['id'] as num).toInt(),
        username: j['username'] ?? '?',
        friendship: j['friendship'] ?? 'none',
        images: _images(j['images']),
        online: j['online'] ?? false,
        status: j['status'] ?? '',
        pronouns: j['pronouns'] ?? '',
        bio: j['bio'] ?? '',
        quote: j['quote'] ?? '',
        unread: (j['unread'] as num?)?.toInt() ?? 0,
      );

  String get statusText {
    if (friendship == 'incoming') return 'Wants to be friends';
    if (friendship == 'outgoing') return 'Request sent';
    if (friendship != 'friends' && friendship != 'self') return 'Not friends yet';
    return switch (status) {
      'dnd' => 'Do not disturb',
      'sleep' => 'Sleeping',
      _ => online ? 'Online' : 'Offline',
    };
  }
}

class ChatMessage {
  final int id;
  final int senderId;
  final String body;

  const ChatMessage(this.id, this.senderId, this.body);

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage((j['id'] as num).toInt(), (j['sender_id'] as num).toInt(), j['body'] ?? '');
}

class ReleaseFile {
  final String file;
  final String sha256;
  final int size;

  const ReleaseFile(this.file, this.sha256, this.size);

  static ReleaseFile? fromJson(dynamic j) => j == null ? null : ReleaseFile(j['file'], j['sha256'], (j['size'] as num).toInt());
}

class ReleaseNote {
  final String version;
  final List<String> changes;

  const ReleaseNote(this.version, this.changes);
}

class Release {
  final String version;
  final List<ReleaseNote> notes;
  final ReleaseFile? android;
  final ReleaseFile? windows;

  const Release(this.version, this.notes, this.android, this.windows);

  factory Release.fromJson(Map<String, dynamic> j) => Release(
        j['version'] ?? '0.0.0',
        [for (final n in (j['notes'] ?? const []) as List) ReleaseNote(n['version'] ?? '', ((n['changes'] ?? const []) as List).cast<String>())],
        ReleaseFile.fromJson(j['android']),
        ReleaseFile.fromJson(j['windows']),
      );
}
