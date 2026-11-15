import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'models.dart';
import 'player_controller.dart';

const _channel = MethodChannel('vortex/media');

/// Phones get a media card through audio_service, connected directly to Vortex's
/// own queue. Windows gets the card in Quick Settings and the volume flyout
/// through a small native bridge.
Future<void> attachMediaControls(PlayerController c) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await AudioService.init(
      builder: () => _PhoneMedia(c),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.shadow.vortex.audio',
        androidNotificationChannelName: 'Vortex playback',
        androidNotificationIcon: 'drawable/ic_notification',
        // Staying in the foreground while paused lets Play and Next keep working
        // from the lock screen, where Android won't let an app start one again.
        androidStopForegroundOnPause: false,
      ),
    );
  }
  if (Platform.isAndroid) _askForNotificationsOnFirstSong(c);
  if (Platform.isWindows) _WindowsMedia(c).start();
}

class _PhoneMedia extends BaseAudioHandler with SeekHandler {
  final PlayerController c;
  String? _trackId;

  _PhoneMedia(this.c) {
    c.addListener(_syncTrack);
    c.player.playbackEventStream.listen((_) => _syncState(), onError: (Object _, StackTrace _) {});
    c.player.playingStream.listen((_) => _syncState());
    c.player.durationStream.listen((_) => _publishTrack());
  }

  void _syncTrack() {
    if (c.current?.id != _trackId) {
      _trackId = c.current?.id;
      _publishTrack();
    }
    _syncState();
  }

  void _publishTrack() {
    final Track? track = c.current;
    if (track == null) {
      mediaItem.add(null);
      return;
    }
    final art = track.artUrl;
    mediaItem.add(MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: c.player.duration ?? (track.duration == null ? null : Duration(seconds: track.duration!)),
      artUri: art.startsWith('https://') ? Uri.parse(art) : null,
    ));
  }

  void _syncState() {
    final player = c.player;
    final loaded = c.current != null;
    // Vortex stops the player between songs. Reporting that as idle would close
    // the card, and Android may refuse to reopen it while the phone is locked.
    final state = switch (player.processingState) {
      ProcessingState.idle => loaded ? AudioProcessingState.loading : AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: state,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
    ));
  }

  @override
  Future<void> play() => c.player.play();

  @override
  Future<void> pause() => c.player.pause();

  @override
  Future<void> seek(Duration position) => c.player.seek(position);

  @override
  Future<void> skipToNext() => c.next();

  @override
  Future<void> skipToPrevious() async => c.previous();

  @override
  Future<void> stop() async {
    await c.player.pause();
    await super.stop();
  }
}

/// Asked when music starts, because that's when the reason for asking is obvious.
void _askForNotificationsOnFirstSong(PlayerController c) {
  late final VoidCallback listener;
  listener = () {
    if (c.current == null) return;
    c.removeListener(listener);
    _channel.invokeMethod('askForNotifications').catchError((_) {});
  };
  c.addListener(listener);
}

class _WindowsMedia {
  final PlayerController c;
  String? _trackId;
  bool? _playing;
  Duration _lastPosition = Duration.zero;

  _WindowsMedia(this.c);

  void start() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'play':
          c.player.play();
        case 'pause':
          c.player.pause();
        case 'next':
          if (c.hasNext) c.next();
        case 'previous':
          c.previous();
        case 'seek':
          c.player.seek(Duration(milliseconds: call.arguments as int));
      }
    });
    c.addListener(_syncTrack);
    c.player.playerStateStream.listen(_syncState);
    c.player.durationStream.listen((_) => _syncTimeline());
    c.player.positionDiscontinuityStream.listen((_) => _syncTimeline());
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (c.player.playing) _syncTimeline();
    });
  }

  Future<void> _send(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod(method, arguments);
    } catch (_) {}
  }

  void _syncTrack() {
    final Track? track = c.current;
    if (track?.id == _trackId) return;
    _trackId = track?.id;
    if (track == null) {
      _send('clear');
      return;
    }
    _send('track', {
      'title': track.title,
      'artist': track.artist,
      'album': track.album ?? '',
      'art': track.artUrl.startsWith('https://') ? track.artUrl : '',
    });
  }

  void _syncState(PlayerState state) {
    if (state.playing == _playing) return;
    _playing = state.playing;
    _send('playing', state.playing);
    _syncTimeline();
  }

  void _syncTimeline() {
    final total = c.player.duration;
    if (total == null) return;
    final position = c.player.position;
    if (position == _lastPosition && c.player.playing) return;
    _lastPosition = position;
    _send('timeline', {'position': position.inMilliseconds, 'duration': total.inMilliseconds});
  }
}
