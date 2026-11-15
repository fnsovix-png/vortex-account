import 'account.dart';
import 'anilist.dart';
import 'kitsu.dart';

class ConnectorResult {
  final bool ok;
  final String message;
  final DateTime at;

  ConnectorResult(this.ok, this.message) : at = DateTime.now();
}

/// One source of anime data or video. Each runs alone, so one failing never touches the others.
abstract class SourceConnector {
  String get id;
  String get name;
  List<String> get domains;
  List<String> get provides;
  List<String> get lacks;

  Future<ConnectorResult> probe();

  Future<ConnectorResult> check() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await probe().timeout(const Duration(seconds: 20));
      } catch (_) {
        if (attempt == 0) await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    return ConnectorResult(false, 'Not answering right now. The rest of Vortex keeps working.');
  }
}

class AniListConnector extends SourceConnector {
  @override
  String get id => 'anilist';
  @override
  String get name => 'AniList';
  @override
  List<String> get domains => const ['anilist.co', 'graphql.anilist.co'];
  @override
  List<String> get provides => const ['Full catalog', 'Search', 'Artwork', 'One entry per show'];
  @override
  List<String> get lacks => const ['Video'];

  @override
  Future<ConnectorResult> probe() async {
    await AniList.ping();
    return ConnectorResult(true, 'Connected');
  }
}

class KitsuConnector extends SourceConnector {
  @override
  String get id => 'kitsu';
  @override
  String get name => 'Kitsu';
  @override
  List<String> get domains => const ['kitsu.io', 'kitsu.app'];
  @override
  List<String> get provides => const ['Episode titles', 'Thumbnails', 'Subtitle and audio info'];
  @override
  List<String> get lacks => const ['Video'];

  @override
  Future<ConnectorResult> probe() async {
    await Kitsu.ping();
    return ConnectorResult(true, 'Connected');
  }
}

/// Official playlists that were confirmed playing, run through the Vortex player.
class OfficialStreamConnector extends SourceConnector {
  final Account account;

  OfficialStreamConnector(this.account);

  @override
  String get id => 'official';
  @override
  String get name => 'Official YouTube playlists';
  @override
  List<String> get domains => const ['youtube.com', 'youtu.be', 'youtube-nocookie.com'];
  @override
  List<String> get provides => const ['Vortex player', 'Saved progress', 'Captions', 'Next episode'];
  @override
  List<String> get lacks => const ['Quality picker', 'Audio tracks'];

  @override
  Future<ConnectorResult> probe() async {
    account.forgetBlocks();
    await account.loadVerified();
    final checked = account.verifiedChecked.isEmpty ? '' : ', checked ${account.verifiedChecked}';
    return ConnectorResult(true, '${account.verified.length} shows confirmed playing$checked');
  }
}

/// A site that was checked and has no authorized way in. It records what was found and never contacts the
/// site, so nothing of theirs can reach your device and nothing of yours reaches them.
class ReviewedConnector extends SourceConnector {
  @override
  final String id;
  @override
  final String name;
  @override
  final List<String> domains;
  final String website;
  final String integration;
  final String reason;

  ReviewedConnector({required this.id, required this.name, required this.domains, required this.website, required this.integration, required this.reason});

  @override
  List<String> get provides => const [];
  @override
  List<String> get lacks => const ['Catalog', 'Episodes', 'Video'];

  @override
  Future<ConnectorResult> probe() async => ConnectorResult(false, 'Not connected. $reason');
}

List<SourceConnector> buildConnectors(Account account) => [
      AniListConnector(),
      KitsuConnector(),
      OfficialStreamConnector(account),
      ReviewedConnector(
        id: 'reanime',
        name: 'Re:ANIME',
        domains: const ['reanime.to'],
        website: 'reanime.to, confirmed',
        integration: 'Has an API, but only for its own site. No access is offered to other apps.',
        reason: 'Its terms ban copying and reverse engineering, and it shows no rights to the anime.',
      ),
      ReviewedConnector(
        id: 'anikoto',
        name: 'AniKoto',
        domains: const ['anikoto.tv', 'anikoto.to', 'anikoto.net', 'anikoto.fun', 'anikoto.bz'],
        website: 'No official site could be confirmed. Many look-alike domains exist.',
        integration: 'None found',
        reason: 'There is no confirmed site to connect to, and no rights shown.',
      ),
      ReviewedConnector(
        id: 'anime-sama',
        name: 'Anime-Sama',
        domains: const ['anime-sama.org', 'anime-sama.fr', 'anime-sama.si'],
        website: 'anime-sama.org, reachable',
        integration: 'None found',
        reason: 'No public integration, and no rights shown.',
      ),
      ReviewedConnector(
        id: 'animegg',
        name: 'AnimeGG',
        domains: const ['animegg.org'],
        website: 'animegg.org, reachable',
        integration: 'None found',
        reason: 'No public integration, and no rights shown.',
      ),
      ReviewedConnector(
        id: 'aniworld',
        name: 'AniWorld',
        domains: const ['aniworld.to'],
        website: 'aniworld.to, reachable',
        integration: 'None found',
        reason: 'It calls its anime licence-free but shows no proof, and offers no public integration.',
      ),
      ReviewedConnector(
        id: 'ani-kage',
        name: 'Ani-Kage',
        domains: const ['anikage.cc', 'anikage.to'],
        website: 'anikage.cc, reachable. anikage.to also uses the name.',
        integration: 'None found',
        reason: 'No public integration, and no rights shown.',
      ),
    ];
