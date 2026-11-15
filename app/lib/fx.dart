import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';

const Color defaultTint = Color(0xFF2F8F63);
const List<Color> defaultPalette = [Color(0xFF2F8F63), Color(0xFF2F6F8F), Color(0xFF6A3FA0), Color(0xFF1F7F7A)];
final Map<String, List<Color>> _paletteCache = {};
const _minColorShare = 0.12;

Color _normalize(HSLColor c) => c.withLightness(c.lightness.clamp(0.32, 0.56)).withSaturation(c.saturation.clamp(0.3, 0.88)).toColor();

Future<List<Color>> coverPalette(String url) => paletteFromUrl(Api.instance.artUrl(url));

Future<List<Color>> paletteFromUrl(String url) async {
  final cached = _paletteCache[url];
  if (cached != null) return cached;
  final completer = Completer<ui.Image>();
  final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
      stream.removeListener(listener);
    },
    onError: (e, _) {
      if (!completer.isCompleted) completer.completeError(e);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  final image = await completer.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return defaultPalette;
  const bins = 12;
  final weights = List<double>.filled(bins, 0);
  final reds = List<double>.filled(bins, 0);
  final greens = List<double>.filled(bins, 0);
  final blues = List<double>.filled(bins, 0);
  final stepX = max(1, image.width ~/ 32);
  final stepY = max(1, image.height ~/ 32);
  var samples = 0;
  var colorful = 0;
  var brightness = 0.0;
  for (var y = 0; y < image.height; y += stepY) {
    for (var x = 0; x < image.width; x += stepX) {
      final o = (y * image.width + x) * 4;
      final color = Color.fromARGB(255, data.getUint8(o), data.getUint8(o + 1), data.getUint8(o + 2));
      final hsv = HSVColor.fromColor(color);
      samples++;
      brightness += hsv.value;
      if (hsv.saturation < 0.15 || hsv.value < 0.12) continue;
      colorful++;
      final bin = (hsv.hue / 360 * bins).floor().clamp(0, bins - 1);
      final weight = hsv.saturation * hsv.value;
      weights[bin] += weight;
      reds[bin] += color.r * weight;
      greens[bin] += color.g * weight;
      blues[bin] += color.b * weight;
    }
  }
  if (samples > 0 && colorful / samples < _minColorShare) {
    final level = (brightness / samples).clamp(0.2, 0.7);
    final grays = [
      for (final scale in const [0.9, 0.6, 1.15, 0.45]) HSLColor.fromAHSL(1, 0, 0, (level * scale).clamp(0.12, 0.72)).toColor(),
    ];
    _paletteCache[url] = grays;
    return grays;
  }
  final ranked = [for (var i = 0; i < bins; i++) i].where((i) => weights[i] > 0).toList()..sort((a, b) => weights[b].compareTo(weights[a]));
  final colors = [
    for (final i in ranked.take(4))
      _normalize(HSLColor.fromColor(Color.from(alpha: 1, red: reds[i] / weights[i], green: greens[i] / weights[i], blue: blues[i] / weights[i]))),
  ];
  if (colors.isEmpty) return defaultPalette;
  final base = HSLColor.fromColor(colors.first);
  const shifts = [34.0, 322.0, 62.0];
  for (var i = 0; colors.length < 4; i++) {
    colors.add(_normalize(base.withHue((base.hue + shifts[i]) % 360)));
  }
  _paletteCache[url] = colors;
  return colors;
}

class _PaletteTween extends Tween<List<Color>> {
  _PaletteTween({super.begin, super.end});

  @override
  List<Color> lerp(double t) => [for (var i = 0; i < end!.length; i++) Color.lerp(begin![i], end![i], t)!];
}

class MeshBackground extends StatefulWidget {
  final ValueListenable<List<Color>> palette;
  final bool animate;

  const MeshBackground({super.key, required this.palette, this.animate = true});

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground> with WidgetsBindingObserver {
  // The blobs drift only a few pixels a second across very soft edges, so ten
  // updates a second looks the same as fifteen and leaves far more frames idle.
  static const _step = Duration(milliseconds: 100);

  final ValueNotifier<double> _time = ValueNotifier(0);
  Timer? _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = widget.animate && _visible ? Timer.periodic(_step, (_) => _time.value += _step.inMilliseconds / 1000) : null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _sync();
  }

  @override
  void didUpdateWidget(MeshBackground old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<List<Color>>(
        valueListenable: widget.palette,
        builder: (context, palette, _) => TweenAnimationBuilder<List<Color>>(
          tween: _PaletteTween(begin: palette, end: palette),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeInOut,
          builder: (context, colors, _) => CustomPaint(
            size: Size.infinite,
            painter: _MeshPainter(_time, colors),
          ),
        ),
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final List<Color> palette;

  _MeshPainter(this.time, this.palette) : super(repaint: time);

  void _blob(Canvas canvas, Offset center, double radius, Color color, double alpha) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: alpha * 0.55), color.withValues(alpha: 0)],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  // These blobs have no sharp detail anywhere, so drawing them at an eighth of
  // the size and stretching the result looks the same and is far cheaper.
  static const _scale = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final recorder = ui.PictureRecorder();
    _paintBlobs(Canvas(recorder)..scale(1 / _scale), size);
    final picture = recorder.endRecording();
    final width = (size.width / _scale).ceil();
    final height = (size.height / _scale).ceil();
    final rough = picture.toImageSync(width, height);
    picture.dispose();
    // Gradients are dithered with fine speckle, which would stretch into a visible
    // grid. Smoothing it while the image is still tiny costs almost nothing.
    final smoother = ui.PictureRecorder();
    Canvas(smoother).drawImage(rough, Offset.zero, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 1.6, sigmaY: 1.6, tileMode: TileMode.clamp));
    final smoothPicture = smoother.endRecording();
    final image = smoothPicture.toImageSync(width, height);
    smoothPicture.dispose();
    rough.dispose();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
    image.dispose();
  }

  void _paintBlobs(Canvas canvas, Size size) {
    final t = time.value;
    final w = size.width, h = size.height;
    final span = max(w, h);
    final first = HSLColor.fromColor(palette[0]);
    final base = first.withLightness(0.045).withSaturation(min(first.saturation, 0.4)).toColor();
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    _blob(canvas, Offset(w * (0.12 + 0.14 * sin(t * 0.21)), h * (0.04 + 0.1 * cos(t * 0.17))), span * 0.68, palette[0], 0.5);
    _blob(canvas, Offset(w * (0.88 + 0.12 * cos(t * 0.15)), h * (0.1 + 0.14 * sin(t * 0.23))), span * 0.58, palette[1], 0.34);
    _blob(canvas, Offset(w * (0.92 + 0.1 * sin(t * 0.13)), h * (0.86 + 0.1 * cos(t * 0.19))), span * 0.5, palette[2], 0.24);
    _blob(canvas, Offset(w * (0.08 + 0.12 * cos(t * 0.11)), h * (0.92 + 0.08 * sin(t * 0.25))), span * 0.5, palette[3], 0.24);
    _blob(canvas, Offset(w * (0.5 + 0.2 * sin(t * 0.09)), h * (0.56 + 0.14 * cos(t * 0.12))), span * 0.5, const Color(0xFF05040A), 0.82);
  }

  @override
  bool shouldRepaint(_MeshPainter old) => !listEquals(old.palette, palette);
}

class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry? padding;

  const Glass({super.key, required this.child, this.radius = 20, this.blur = 26, this.opacity = 0.07, this.padding});

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: shape,
            color: Colors.white.withValues(alpha: opacity),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class EqualizerBars extends StatefulWidget {
  final double size;
  final Color? color;
  final bool active;

  const EqualizerBars({super.key, this.size = 16, this.color, this.active = true});

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _anim.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.active && !_anim.isAnimating) _anim.repeat();
    if (!widget.active && _anim.isAnimating) _anim.stop();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(size: Size.square(widget.size), painter: _EqPainter(_anim, widget.color ?? AppColors.accent)),
    );
  }
}

class _EqPainter extends CustomPainter {
  final Animation<double> anim;
  final Color color;

  _EqPainter(this.anim, this.color) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 4;
    final width = size.width / (bars * 1.6);
    final paint = Paint()..color = color;
    for (var i = 0; i < bars; i++) {
      final wave = 0.5 + 0.5 * sin(anim.value * 2 * pi * (i.isEven ? 2 : 3) + i * 1.3);
      final h = size.height * (0.25 + 0.75 * wave);
      final x = i * width * 1.6;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h, width, h), Radius.circular(width / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) => old.color != color;
}

class VortexRing extends StatefulWidget {
  final double size;
  final Color tint;
  final bool active;

  const VortexRing({super.key, required this.size, required this.tint, required this.active});

  @override
  State<VortexRing> createState() => _VortexRingState();
}

class _VortexRingState extends State<VortexRing> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void initState() {
    super.initState();
    if (widget.active) _anim.repeat();
  }

  @override
  void didUpdateWidget(VortexRing old) {
    super.didUpdateWidget(old);
    if (widget.active && !_anim.isAnimating) _anim.repeat();
    if (!widget.active && _anim.isAnimating) _anim.stop();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(size: Size.square(widget.size), painter: _RingPainter(_anim, widget.tint)),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Animation<double> anim;
  final Color tint;

  _RingPainter(this.anim, this.tint) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.width / 2;
    final hsl = HSLColor.fromColor(tint);
    final bright = hsl.withLightness(0.72).withSaturation(hsl.saturation < 0.12 ? 0 : 0.9).toColor();
    const rings = 4;
    for (var i = 0; i < rings; i++) {
      final direction = i.isEven ? 1 : -1;
      final rotation = anim.value * 2 * pi * direction * (i + 1) + i * 1.1;
      final radius = base * (0.8 + i * 0.065);
      final rect = Rect.fromCircle(center: center, radius: radius);
      final alpha = 0.75 - i * 0.16;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = base * (0.014 - i * 0.002)
        ..shader = SweepGradient(
          transform: GradientRotation(rotation),
          colors: [bright.withValues(alpha: 0), bright.withValues(alpha: alpha), AppColors.accent.withValues(alpha: alpha), bright.withValues(alpha: 0)],
          stops: const [0, 0.4, 0.62, 0.8],
        ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.tint != tint;
}

class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int index;

  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    final delay = min(index, 8) * 70;
    final total = 460 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: child),
      ),
    );
  }
}

class Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const Shimmer({super.key, required this.width, required this.height, this.radius = 12});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-2 + _anim.value * 4, -0.3),
            end: Alignment(-1 + _anim.value * 4, 0.3),
            colors: const [Color(0x12FFFFFF), Color(0x2EFFFFFF), Color(0x12FFFFFF)],
          ),
        ),
      ),
    );
  }
}

class WaveSeekBar extends StatefulWidget {
  final String seed;
  final double progress;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final double height;

  const WaveSeekBar({super.key, required this.seed, required this.progress, required this.onChanged, required this.onChangeEnd, this.height = 44});

  @override
  State<WaveSeekBar> createState() => _WaveSeekBarState();
}

class _WaveSeekBarState extends State<WaveSeekBar> {
  double? _last;

  double _fraction(Offset local, double width) => (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => widget.onChangeEnd(_fraction(d.localPosition, box.maxWidth)),
          onHorizontalDragStart: (d) {
            _last = _fraction(d.localPosition, box.maxWidth);
            widget.onChanged(_last!);
          },
          onHorizontalDragUpdate: (d) {
            _last = _fraction(d.localPosition, box.maxWidth);
            widget.onChanged(_last!);
          },
          onHorizontalDragEnd: (_) {
            if (_last != null) widget.onChangeEnd(_last!);
            _last = null;
          },
          child: CustomPaint(size: Size(box.maxWidth, widget.height), painter: _WavePainter(widget.seed, widget.progress)),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final String seed;
  final double progress;

  const _WavePainter(this.seed, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const gap = 2.0;
    final count = (size.width / (barWidth + gap)).floor();
    final random = Random(seed.hashCode);
    final played = Paint()
      ..shader = LinearGradient(colors: [AppColors.accent, Colors.white]).createShader(Rect.fromLTWH(0, 0, max(size.width * progress, 1), size.height));
    final rest = Paint()..color = const Color(0x40FFFFFF);
    var previous = 0.5;
    for (var i = 0; i < count; i++) {
      final envelope = 0.45 + 0.55 * sin(pi * i / count);
      previous = previous * 0.45 + random.nextDouble() * 0.55;
      final h = max(size.height * previous * envelope, 3.0);
      final x = i * (barWidth + gap);
      final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, barWidth, h), const Radius.circular(2));
      canvas.drawRRect(rrect, (i + 0.5) / count <= progress ? played : rest);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.seed != seed || old.progress != progress;
}
