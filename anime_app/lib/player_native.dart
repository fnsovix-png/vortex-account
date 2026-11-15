import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_windows/webview_windows.dart' as desk;

import 'account.dart';

bool get canPlayInApp => Platform.isAndroid || Platform.isIOS || Platform.isWindows;

const bool playerHasOwnControls = false;

/// What the YouTube player is doing right now.
class PlayerStatus {
  final bool playing;
  final bool buffering;
  final bool ended;
  final double position;
  final double duration;
  final int? error;
  final bool ready;
  final int? episodesInSource;
  final int? index;

  const PlayerStatus({this.playing = false, this.buffering = true, this.ended = false, this.position = 0, this.duration = 0, this.error, this.ready = false, this.episodesInSource, this.index});
}

class YouTubeHandle {
  _YouTubeViewState? _state;

  void play() => _state?._run('p.playVideo()');
  void pause() => _state?._run('p.pauseVideo()');
  void seek(double seconds) => _state?._run('p.seekTo($seconds,true)');
  void captions(bool on) => _state?._run(on ? "p.loadModule('captions');p.setOption('captions','track',{languageCode:'en'})" : "p.unloadModule('captions')");
  void item(int index, double start) => _state?._run('p.playVideoAt($index);if($start>0){setTimeout(function(){p.seekTo($start,true)},900)}');
}

/// YouTube's own player through its official API, so Vortex can draw the controls and save your place.
class YouTubeView extends StatefulWidget {
  final String playlist;
  final int index;
  final double start;
  final YouTubeHandle handle;
  final ValueChanged<PlayerStatus> onStatus;

  const YouTubeView({super.key, required this.playlist, required this.index, required this.start, required this.handle, required this.onStatus});

  @override
  State<YouTubeView> createState() => _YouTubeViewState();
}

class _YouTubeViewState extends State<YouTubeView> {
  WebViewController? _web;
  desk.WebviewController? _desk;
  bool _deskReady = false;
  bool _ready = false;

  String get _page => '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="strict-origin-when-cross-origin"><style>html,body,#v{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}</style></head><body><div id="v"></div><script>
var p,ended=false;function send(o){Bridge.postMessage(JSON.stringify(o))}
function onYouTubeIframeAPIReady(){p=new YT.Player('v',{host:'https://www.youtube-nocookie.com',width:'100%',height:'100%',playerVars:{listType:'playlist',list:${jsonEncode(widget.playlist)},playsinline:1,rel:0,controls:0,fs:0,modestbranding:1,iv_load_policy:3,autoplay:1,origin:${jsonEncode(serverUrl)}},events:{
onReady:function(){send({t:'ready'});${widget.index > 0 || widget.start >= 1 ? "p.loadPlaylist({listType:'playlist',list:${jsonEncode(widget.playlist)},index:${widget.index},startSeconds:${widget.start.floor()}})" : "p.playVideo()"}},
onError:function(e){send({t:'error',code:e.data})},
onStateChange:function(e){send({t:'state',s:e.data})}}})}
setInterval(function(){if(p&&p.getCurrentTime)send({t:'time',p:p.getCurrentTime()||0,d:p.getDuration()||0,c:(p.getPlaylist()||[]).length,i:p.getPlaylistIndex()})},700);
</script><script src="https://www.youtube.com/iframe_api"></script></body></html>''';

  PlayerStatus _status = const PlayerStatus();

  void _emit(PlayerStatus s) {
    _status = s;
    widget.onStatus(s);
  }

  void _message(JavaScriptMessage m) => _handle(m.message);

  void _handle(dynamic raw) {
    final j = jsonDecode(raw is String ? raw : jsonEncode(raw)) as Map<String, dynamic>;
    final s = _status;
    switch (j['t']) {
      case 'ready':
        _ready = true;
        _emit(PlayerStatus(playing: s.playing, buffering: false, position: s.position, duration: s.duration, ready: true, episodesInSource: s.episodesInSource, index: s.index));
      case 'error':
        _emit(PlayerStatus(error: (j['code'] as num).toInt(), ready: s.ready, buffering: false));
      case 'state':
        final v = (j['s'] as num).toInt();
        _emit(PlayerStatus(playing: v == 1, buffering: v == 3, ended: v == 0, position: s.position, duration: s.duration, ready: s.ready, episodesInSource: s.episodesInSource, index: s.index));
      case 'time':
        _emit(PlayerStatus(playing: s.playing, buffering: s.buffering, ended: s.ended, position: (j['p'] as num).toDouble(), duration: (j['d'] as num).toDouble(), error: s.error, ready: s.ready, episodesInSource: (j['c'] as num?)?.toInt() ?? s.episodesInSource, index: (j['i'] as num?)?.toInt()));
    }
  }

  void _run(String js) {
    if (!_ready) return;
    _web?.runJavaScript(js);
    _desk?.executeScript(js);
  }

  @override
  void initState() {
    super.initState();
    widget.handle._state = this;
    if (Platform.isWindows) {
      _startDesk();
      return;
    }
    final web = WebViewController();
    _web = web;
    web
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Bridge', onMessageReceived: _message)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (r) {
        if (!r.isMainFrame || r.url.startsWith('about:') || r.url.startsWith(serverUrl)) return NavigationDecision.navigate;
        launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication);
        return NavigationDecision.prevent;
      }));
    final platform = web.platform;
    if (platform is AndroidWebViewController) platform.setMediaPlaybackRequiresUserGesture(false);
    web.loadHtmlString(_page, baseUrl: serverUrl);
  }

  static bool _deskConfigured = false;

  Future<void> _startDesk() async {
    if (!_deskConfigured) {
      _deskConfigured = true;
      // Lets an episode start by itself, the same as it does on phones.
      await desk.WebviewController.initializeEnvironment(additionalArguments: '--autoplay-policy=no-user-gesture-required');
    }
    final web = desk.WebviewController();
    _desk = web;
    await web.initialize();
    web.webMessage.listen(_handle);
    await web.setBackgroundColor(Colors.black);
    await web.setPopupWindowPolicy(desk.WebviewPopupWindowPolicy.deny);
    final query = Uri(queryParameters: {'list': widget.playlist, 'index': '${widget.index}', 'start': '${widget.start.floor()}'}).query;
    await web.loadUrl('$serverUrl/anime/player.html?$query');
    if (mounted) setState(() => _deskReady = true);
  }

  @override
  void dispose() {
    if (widget.handle._state == this) widget.handle._state = null;
    _desk?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) return _deskReady ? desk.Webview(_desk!) : const ColoredBox(color: Colors.black);
    return WebViewWidget(controller: _web!);
  }
}
