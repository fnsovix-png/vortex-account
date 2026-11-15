import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';
import 'ui.dart';

const _reviewedDomains = ['reanime.to', 'anikoto.tv', 'anikoto.to', 'anikoto.net', 'anikoto.fun', 'anikoto.bz', 'anime-sama.org', 'anime-sama.fr', 'anime-sama.si', 'animegg.org', 'aniworld.to', 'anikage.cc', 'anikage.to'];
const _videoEndings = ['.mp4', '.mkv', '.webm', '.mov', '.m4v', '.avi', '.m3u8', '.mpd', '.ts'];

/// Checks a pasted link is a direct link to a video. Returns what's wrong, or null when it's fine.
String? checkVideoLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) return 'That doesn\'t look like a link.';
  if (uri.userInfo.isNotEmpty) return 'Links with a password inside them aren\'t allowed.';
  final host = uri.host.toLowerCase();
  if (_reviewedDomains.any((d) => host == d || host.endsWith('.$d'))) return 'That site has no rights to its anime, so it can\'t be added.';
  final path = uri.path.toLowerCase();
  if (!_videoEndings.any(path.endsWith)) return 'Paste a direct link to a video file, ending in something like .mp4 or .m3u8.';
  return null;
}

class LibraryItem {
  final String id;
  String title;
  final String source;
  final bool isLink;
  double position;
  double duration;
  bool finished;

  LibraryItem({required this.id, required this.title, required this.source, required this.isLink, this.position = 0, this.duration = 0, this.finished = false});

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        id: j['id'],
        title: j['title'],
        source: j['source'],
        isLink: j['isLink'] ?? false,
        position: (j['position'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        finished: j['finished'] ?? false,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'source': source, 'isLink': isLink, 'position': position, 'duration': duration, 'finished': finished};
}

/// Your own videos. This list and your place in each video are kept only on this device.
class MyLibrary extends ChangeNotifier {
  final SharedPreferences prefs;
  List<LibraryItem> items = [];

  MyLibrary(this.prefs) {
    final saved = prefs.getString('my_library');
    if (saved != null) items = [for (final j in jsonDecode(saved) as List) LibraryItem.fromJson(j)];
  }

  void save() {
    prefs.setString('my_library', jsonEncode([for (final i in items) i.toJson()]));
    notifyListeners();
  }

  void add(String title, String source, bool isLink) {
    if (items.any((i) => i.source == source)) return;
    items = [...items, LibraryItem(id: '${DateTime.now().microsecondsSinceEpoch}', title: title, source: source, isLink: isLink)];
    save();
  }

  void remove(LibraryItem item) {
    items = items.where((i) => i != item).toList();
    save();
  }
}

String _nameFrom(String source) {
  final last = Uri.decodeComponent(source.split(RegExp(r'[/\\]')).last.split('?').first);
  final dot = last.lastIndexOf('.');
  final name = (dot > 0 ? last.substring(0, dot) : last).replaceAll(RegExp(r'[._]+'), ' ').trim();
  return name.isEmpty ? 'Video' : name;
}

String _clock(double seconds) {
  final s = seconds.floor();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$r' : '$m:$r';
}

class MyLibraryScreen extends StatefulWidget {
  final SharedPreferences prefs;

  const MyLibraryScreen({super.key, required this.prefs});

  @override
  State<MyLibraryScreen> createState() => _MyLibraryScreenState();
}

class _MyLibraryScreenState extends State<MyLibraryScreen> {
  late final MyLibrary _library = MyLibrary(widget.prefs);

  Future<void> _addFiles() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: true);
    if (picked == null) return;
    for (final f in picked.files) {
      if (f.path != null) _library.add(_nameFrom(f.name), f.path!, false);
    }
  }

  Future<void> _addLink() async {
    final field = TextEditingController();
    String? error;
    final link = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setInner) => AlertDialog(
          title: const Text('ADD A VIDEO LINK', style: TextStyle(fontFamily: 'Bebas', fontSize: 28)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('A direct link to a video you own or have permission to watch, like one on your own home server.', style: TextStyle(color: Palette.muted, fontSize: 13, height: 1.4)),
                const SizedBox(height: 12),
                TextField(controller: field, autofocus: true, autocorrect: false, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://')),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Palette.danger, fontSize: 13))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final problem = checkVideoLink(field.text);
                if (problem != null) {
                  setInner(() => error = problem);
                } else {
                  Navigator.pop(dialog, field.text.trim());
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    field.dispose();
    if (link != null) _library.add(_nameFrom(link), link, true);
  }

  Future<void> _rename(LibraryItem item) async {
    final field = TextEditingController(text: item.title);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('RENAME', style: TextStyle(fontFamily: 'Bebas', fontSize: 28)),
        content: TextField(controller: field, autofocus: true, maxLength: 120, decoration: const InputDecoration(counterText: '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, field.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    field.dispose();
    if (name != null && name.isNotEmpty) {
      item.title = name;
      _library.save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = pageSide(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: Palette.background, scrolledUnderElevation: 0, title: const Text('MY LIBRARY', style: TextStyle(fontFamily: 'Bebas', fontSize: 28, letterSpacing: 0.6))),
      body: kIsWeb
          ? const EmptyBox(icon: Icons.video_library_rounded, title: 'Open the app for this', body: 'My Library works in the phone and PC apps.')
          : ListenableBuilder(
              listenable: _library,
              builder: (context, _) => ListView(
                padding: EdgeInsets.fromLTRB(side, 4, side, 40),
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_rounded, size: 15, color: Palette.lavender),
                      SizedBox(width: 6),
                      Expanded(child: Text('Your videos. Kept only on this device.', style: TextStyle(color: Palette.lavender, fontSize: 13, fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(onPressed: _addFiles, icon: const Icon(Icons.folder_open_rounded), label: const Text('Add videos')),
                      OutlinedButton.icon(onPressed: _addLink, icon: const Icon(Icons.link_rounded), label: const Text('Add a link')),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_library.items.isEmpty)
                    const EmptyBox(icon: Icons.video_library_rounded, title: 'Nothing here yet', body: 'Add videos from this device, or a link to your own.')
                  else
                    for (var i = 0; i < _library.items.length; i++) _row(i),
                ],
              ),
            ),
    );
  }

  Widget _row(int index) {
    final item = _library.items[index];
    final progress = item.duration > 0 ? (item.position / item.duration).clamp(0.0, 1.0) : 0.0;
    final detail = item.finished ? 'Watched' : (item.position > 5 ? 'Resume at ${_clock(item.position)}' : (item.isLink ? 'Your link' : 'On this device'));
    return Semantics(
      button: true,
      label: 'Play ${item.title}',
      child: Pressable(
        scale: 0.985,
        onTap: () => go(context, LibraryPlayerScreen(library: _library, index: index)),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
          decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: Palette.line)),
          child: Row(
            children: [
              const Icon(Icons.play_circle_fill_rounded, color: Palette.bright, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(detail, style: const TextStyle(color: Palette.muted, fontSize: 12)),
                    if (progress > 0 && !item.finished) ...[
                      const SizedBox(height: 6),
                      ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: progress, minHeight: 3, color: Palette.purple, backgroundColor: Palette.line)),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Change',
                color: Palette.surface,
                icon: const Icon(Icons.more_vert_rounded, color: Palette.muted),
                onSelected: (v) => v == 'rename' ? _rename(item) : _library.remove(item),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: Palette.danger))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full Vortex player, with real track, quality and volume control.
class LibraryPlayerScreen extends StatefulWidget {
  final MyLibrary library;
  final int index;

  const LibraryPlayerScreen({super.key, required this.library, required this.index});

  @override
  State<LibraryPlayerScreen> createState() => _LibraryPlayerScreenState();
}

class _LibraryPlayerScreenState extends State<LibraryPlayerScreen> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final _subs = <StreamSubscription<dynamic>>[];
  late int _index = widget.index;
  bool _playing = false;
  bool _buffering = true;
  double _position = 0;
  double _duration = 0;
  double _volume = 100;
  double? _dragging;
  bool _controls = true;
  bool _full = false;
  String? _error;
  Timer? _hide;
  DateTime _lastSave = DateTime.now();
  Tracks _tracks = const Tracks();
  Track _track = const Track();

  List<LibraryItem> get _items => widget.library.items;
  LibraryItem get _item => _items[_index];

  @override
  void initState() {
    super.initState();
    final s = _player.stream;
    _subs.addAll([
      s.playing.listen((v) => _set(() => _playing = v)),
      s.buffering.listen((v) => _set(() => _buffering = v)),
      s.duration.listen((v) => _set(() => _duration = v.inMilliseconds / 1000)),
      s.position.listen(_onPosition),
      s.volume.listen((v) => _set(() => _volume = v)),
      s.tracks.listen((v) => _set(() => _tracks = v)),
      s.track.listen((v) => _set(() => _track = v)),
      s.error.listen((_) => _set(() => _error = 'This video couldn\'t be played. Check the file or link.')),
      s.completed.listen((done) {
        if (done) _finished();
      }),
    ]);
    _open();
    _scheduleHide();
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  void _open() {
    _error = null;
    final item = _item;
    final start = !item.finished && item.position > 5 ? Duration(seconds: item.position.floor()) : null;
    _player.open(Media(item.source, start: start));
  }

  void _onPosition(Duration p) {
    final seconds = p.inMilliseconds / 1000;
    _set(() => _position = seconds);
    if (_duration > 0 && DateTime.now().difference(_lastSave).inSeconds >= 5) _store();
  }

  void _store() {
    _lastSave = DateTime.now();
    if (_duration <= 0) return;
    _item
      ..position = _position
      ..duration = _duration;
    if (_position / _duration > 0.95) _item.finished = true;
    widget.library.save();
  }

  void _finished() {
    _item
      ..finished = true
      ..position = 0;
    widget.library.save();
    if (_index + 1 < _items.length) _goTo(_index + 1);
  }

  void _goTo(int index) {
    _store();
    _set(() {
      _index = index;
      _position = 0;
      _duration = 0;
      _buffering = true;
    });
    _open();
    _touch();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (_playing && _dragging == null) _set(() => _controls = false);
    });
  }

  void _touch() {
    _set(() => _controls = true);
    _scheduleHide();
  }

  void _skip(double by) {
    _player.seek(Duration(milliseconds: ((_position + by).clamp(0.0, _duration) * 1000).round()));
    _touch();
  }

  void _setFull(bool value) {
    if (value) {
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations(const []);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _set(() => _full = value);
  }

  @override
  void dispose() {
    _store();
    _hide?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _trackName(String? title, String? language, String id, int fallback, String word) {
    const names = {'en': 'English', 'ja': 'Japanese', 'jp': 'Japanese', 'fr': 'French', 'es': 'Spanish', 'de': 'German', 'it': 'Italian', 'pt': 'Portuguese', 'ko': 'Korean', 'zh': 'Chinese', 'ru': 'Russian', 'ar': 'Arabic'};
    final parts = [if (title != null && title.isNotEmpty) title, if (language != null && language.isNotEmpty) names[language.toLowerCase()] ?? language];
    return parts.isEmpty ? '$word $fallback' : parts.join(' · ');
  }

  void _chooser<T>(String heading, List<T> options, T current, String Function(T, int) name, void Function(T) pick) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 6), child: Align(alignment: Alignment.centerLeft, child: Text(heading.toUpperCase(), style: const TextStyle(fontFamily: 'Bebas', fontSize: 26)))),
              for (var i = 0; i < options.length; i++)
                ListTile(
                  title: Text(name(options[i], i), style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: options[i] == current ? const Icon(Icons.check_rounded, color: Palette.bright) : null,
                  onTap: () {
                    Navigator.pop(sheet);
                    pick(options[i]);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _subtitleSheet() {
    final options = _tracks.subtitle.where((t) => t.id != 'auto').toList();
    _chooser<SubtitleTrack>('Subtitles', options, _track.subtitle, (t, i) => t.id == 'no' ? 'Off' : _trackName(t.title, t.language, t.id, i, 'Subtitle'), _player.setSubtitleTrack);
  }

  void _audioSheet() {
    final options = _tracks.audio.where((t) => t.id != 'no').toList();
    _chooser<AudioTrack>('Audio', options, _track.audio, (t, i) => t.id == 'auto' ? 'Automatic' : _trackName(t.title, t.language, t.id, i, 'Audio'), _player.setAudioTrack);
  }

  void _qualitySheet() {
    final options = _tracks.video.where((t) => t.id != 'no').toList();
    _chooser<VideoTrack>('Quality', options, _track.video, (t, i) => t.id == 'auto' ? 'Automatic' : (t.h != null ? '${t.h}p' : _trackName(t.title, null, t.id, i, 'Quality')), _player.setVideoTrack);
  }

  void _volumeSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setInner) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.volume_up_rounded),
                Expanded(
                  child: Slider(
                    value: _volume.clamp(0.0, 100.0),
                    max: 100,
                    activeColor: Palette.purple,
                    onChanged: (v) {
                      _player.setVolume(v);
                      setInner(() => _volume = v);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stage() {
    final at = _dragging ?? _position;
    final hasNext = _index + 1 < _items.length;
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
        GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _controls ? _set(() => _controls = false) : _touch()),
        IgnorePointer(
          ignoring: !_controls,
          child: AnimatedOpacity(
            opacity: _controls ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.3, 0.65, 1], colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xD9000000)])),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 8,
                    child: Row(
                      children: [
                        IconButton(tooltip: 'Back', onPressed: () => _full ? _setFull(false) : Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                        Expanded(child: Text(_item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                      ],
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(tooltip: 'Previous', iconSize: 30, onPressed: _index > 0 ? () => _goTo(_index - 1) : null, icon: const Icon(Icons.skip_previous_rounded)),
                        IconButton(tooltip: 'Back 10 seconds', iconSize: 32, onPressed: () => _skip(-10), icon: const Icon(Icons.replay_10_rounded)),
                        const SizedBox(width: 8),
                        Pressable(
                          onTap: () {
                            _player.playOrPause();
                            _touch();
                          },
                          child: Container(
                            width: 64,
                            height: 64,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(color: Palette.purple, shape: BoxShape.circle),
                            child: _buffering && !_playing ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)) : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 36),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(tooltip: 'Forward 10 seconds', iconSize: 32, onPressed: () => _skip(10), icon: const Icon(Icons.forward_10_rounded)),
                        IconButton(tooltip: 'Next', iconSize: 30, onPressed: hasNext ? () => _goTo(_index + 1) : null, icon: const Icon(Icons.skip_next_rounded)),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 2,
                    bottom: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(_clock(at), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(trackHeight: 3, activeTrackColor: Palette.purple, inactiveTrackColor: const Color(0x55FFFFFF), thumbColor: Colors.white, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 12)),
                                child: Slider(
                                  value: _duration <= 0 ? 0 : at.clamp(0.0, _duration),
                                  max: _duration <= 0 ? 1 : _duration,
                                  onChangeStart: (_) => _hide?.cancel(),
                                  onChanged: _duration <= 0 ? null : (v) => _set(() => _dragging = v),
                                  onChangeEnd: (v) {
                                    _player.seek(Duration(milliseconds: (v * 1000).round()));
                                    _set(() => _dragging = null);
                                    _scheduleHide();
                                  },
                                ),
                              ),
                            ),
                            Text(_clock(_duration), style: const TextStyle(fontSize: 12, color: Color(0xCCFFFFFF))),
                            const SizedBox(width: 6),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(tooltip: 'Volume', visualDensity: VisualDensity.compact, onPressed: _volumeSheet, icon: const Icon(Icons.volume_up_rounded, size: 21)),
                            IconButton(tooltip: 'Subtitles', visualDensity: VisualDensity.compact, onPressed: _subtitleSheet, icon: const Icon(Icons.closed_caption_rounded, size: 21)),
                            IconButton(tooltip: 'Audio', visualDensity: VisualDensity.compact, onPressed: _audioSheet, icon: const Icon(Icons.record_voice_over_rounded, size: 21)),
                            IconButton(tooltip: 'Quality', visualDensity: VisualDensity.compact, onPressed: _qualitySheet, icon: const Icon(Icons.high_quality_rounded, size: 21)),
                            IconButton(tooltip: _full ? 'Exit full screen' : 'Full screen', visualDensity: VisualDensity.compact, onPressed: () => _setFull(!_full), icon: Icon(_full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, size: 23)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final fit = size.width * 9 / 16;
    final height = _full ? size.height : (fit > size.height * 0.68 ? size.height * 0.68 : fit);
    return PopScope(
      canPop: !_full,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _full) _setFull(false);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _player.playOrPause,
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _skip(10),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _skip(-10),
          const SingleActivator(LogicalKeyboardKey.keyF): () => _setFull(!_full),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              top: !_full,
              bottom: false,
              left: !_full,
              right: !_full,
              child: Column(
                children: [
                  SizedBox(width: double.infinity, height: height, child: _stage()),
                  if (!_full)
                    Expanded(
                      child: ColoredBox(
                        color: Palette.background,
                        child: ListenableBuilder(
                          listenable: widget.library,
                          builder: (context, _) => ListView(
                            padding: EdgeInsets.fromLTRB(pageSide(context), 16, pageSide(context), 30),
                            children: [
                              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: Palette.danger, fontWeight: FontWeight.w600))),
                              Text(_item.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4, height: 1.15)),
                              const SizedBox(height: 18),
                              const Text('UP NEXT', style: TextStyle(fontFamily: 'Bebas', fontSize: 24, color: Palette.lavender)),
                              const SizedBox(height: 8),
                              for (var i = 0; i < _items.length; i++)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(i == _index ? Icons.equalizer_rounded : Icons.play_arrow_rounded, color: i == _index ? Palette.bright : Palette.muted),
                                  title: Text(_items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: i == _index ? FontWeight.w800 : FontWeight.w500)),
                                  onTap: i == _index ? null : () => _goTo(i),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
