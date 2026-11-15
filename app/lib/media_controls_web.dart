import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:just_audio/just_audio.dart';

import 'player_controller.dart';

@JS('navigator.mediaSession')
external JSObject? get _session;

@JS('MediaMetadata')
extension type _Metadata._(JSObject _) implements JSObject {
  external factory _Metadata(JSAny init);
}

/// Gives the website version the now-playing card on the iPhone and iPad lock
/// screen and Control Center, and in browsers' media controls.
Future<void> attachMediaControls(PlayerController c) async {
  final session = _session;
  if (session == null) return;

  void handle(String action, void Function(JSObject? details) run) {
    try {
      session.callMethod('setActionHandler'.toJS, action.toJS, run.toJS);
    } catch (_) {}
  }

  handle('play', (_) => c.player.play());
  handle('pause', (_) => c.player.pause());
  handle('nexttrack', (_) {
    if (c.hasNext) c.next();
  });
  handle('previoustrack', (_) => c.previous());
  handle('seekto', (details) {
    final seconds = details?['seekTime'];
    if (seconds.isA<JSNumber>()) c.player.seek(Duration(milliseconds: ((seconds as JSNumber).toDartDouble * 1000).round()));
  });

  String? trackId;
  void syncTrack() {
    final track = c.current;
    if (track?.id == trackId) return;
    trackId = track?.id;
    if (track == null) {
      session['metadata'] = null;
      return;
    }
    session['metadata'] = _Metadata(
      {
        'title': track.title,
        'artist': track.artist,
        'album': track.album ?? '',
        'artwork': [
          if (track.artUrl.startsWith('https://')) {'src': track.artUrl, 'sizes': '544x544'},
        ],
      }.jsify()!,
    );
  }

  void syncPosition() {
    final total = c.player.duration;
    if (total == null || total == Duration.zero || !session.has('setPositionState')) return;
    final position = c.player.position;
    try {
      session.callMethod(
        'setPositionState'.toJS,
        {
          'duration': total.inMilliseconds / 1000,
          'playbackRate': c.speed,
          'position': position > total ? total.inMilliseconds / 1000 : position.inMilliseconds / 1000,
        }.jsify(),
      );
    } catch (_) {}
  }

  c.addListener(syncTrack);
  c.player.playerStateStream.listen((PlayerState state) {
    session['playbackState'] = (state.playing ? 'playing' : 'paused').toJS;
    syncPosition();
  });
  c.player.durationStream.listen((_) => syncPosition());
  c.player.positionDiscontinuityStream.listen((_) => syncPosition());
  Timer.periodic(const Duration(seconds: 10), (_) {
    if (c.player.playing) syncPosition();
  });
}
