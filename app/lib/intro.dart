import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'branding.dart';

const double _impact = 1.42;
const double _floodStart = 2.55;
const double _floodEnd = 3.0;
const double _end = 3.4;
const _holdFor = Duration(milliseconds: 950);
const _lime = Color(0xFFB6FF3C);
const _green = Color(0xFF2FD64A);
const _ink = Color(0xFF071307);

const _quotes = [
  'Every song is a place you can go back to.',
  'Turn it up and let the world go quiet.',
  'Some days only the right song will do.',
  'Music remembers what you forget.',
  'One more song. Then one more.',
  'Press play. Everything else can wait.',
  'Your day deserves a better soundtrack.',
  'Feel it before you hear it.',
];

double _span(double t, double from, double to) => ((t - from) / (to - from)).clamp(0.0, 1.0);

/// The opening sequence. Sparks spiral in, collapse to a point and blast outward,
/// the logo builds itself, then a green wave turns the whole screen into the icon.
class IntroOverlay extends StatefulWidget {
  /// The app underneath can start drawing. Called while this screen still fully
  /// covers it, so its heavy first frame can't be seen as a freeze.
  final VoidCallback onReveal;
  final VoidCallback onDone;

  const IntroOverlay({super.key, required this.onReveal, required this.onDone});

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay> with TickerProviderStateMixin {
  late final AnimationController _time = AnimationController(vsync: this, upperBound: _end, duration: const Duration(milliseconds: 3400));
  late final AnimationController _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final String _quote = _quotes[Random().nextInt(_quotes.length)];
  ui.FragmentShader? _shader;
  bool _ready = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/intro.frag');
      _shader = program.fragmentShader();
    } catch (_) {}
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onReveal();
      widget.onDone();
      return;
    }
    setState(() => _ready = true);
    await _time.forward().orCancel.catchError((_) {});
    if (!mounted || _leaving) return;
    await Future<void>.delayed(_holdFor);
    if (mounted) _leave();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _time.value = _end;
    widget.onReveal();
    // Give the app a moment to draw its first frame behind this finished screen.
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    await _exit.forward().orCancel.catchError((_) {});
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _time.dispose();
    _exit.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = ReverseAnimation(CurvedAnimation(parent: _exit, curve: Curves.easeIn));
    final grow = Tween(begin: 1.0, end: 1.07).animate(CurvedAnimation(parent: _exit, curve: Curves.easeIn));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _ready ? _leave : null,
      child: FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: grow,
          // The finished screen stays cached here, so fading it out costs almost nothing.
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: _time,
                  builder: (context, _) => CustomPaint(painter: _IntroPainter(_time.value, _shader)),
                ),
                _Quote(time: _time, quote: _quote),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  final Animation<double> time;
  final String quote;

  const _Quote({required this.time, required this.quote});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 56;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 0, 32, bottom),
        child: AnimatedBuilder(
          animation: time,
          builder: (context, child) {
            final show = Curves.easeOutCubic.transform(_span(time.value, 2.85, _end));
            if (show <= 0) return const SizedBox.shrink();
            return Opacity(opacity: show, child: Transform.translate(offset: Offset(0, (1 - show) * 14), child: child));
          },
          child: Material(
            type: MaterialType.transparency,
            child: Text(
              quote,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontSize: 17, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.2),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPainter extends CustomPainter {
  final double t;
  final ui.FragmentShader? shader;

  _IntroPainter(this.t, this.shader);

  double get _after => t - _impact;

  @override
  void paint(Canvas canvas, Size size) {
    final flood = Curves.easeInCubic.transform(_span(t, _floodStart, _floodEnd));
    final s = shader;
    if (s != null) {
      s.setFloat(0, size.width);
      s.setFloat(1, size.height);
      s.setFloat(2, t);
      s.setFloat(3, _impact);
      s.setFloat(4, flood);
      canvas.drawRect(Offset.zero & size, Paint()..shader = s);
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = Color.lerp(const Color(0xFF040507), _green, flood)!);
    }
    if (_after >= 0) _paintLogo(canvas, size);
  }

  void _paintLogo(Canvas canvas, Size size) {
    final unit = min(size.width, size.height);
    final after = _after;
    // The logo goes dark as the green wave passes through it.
    final dark = _span(t, _floodStart + 0.1, _floodStart + 0.36);
    // The hit shakes the whole camera, then settles.
    final shakePower = exp(-after * 7) * unit * 0.016;
    final shake = Offset(sin(after * 71) * shakePower, cos(after * 57) * shakePower);

    canvas.save();
    canvas.translate(size.width / 2 + shake.dx, size.height * 0.46 + shake.dy);
    final mark = unit * 0.64;
    _paintMark(canvas, mark, after, dark);
    _paintName(canvas, unit, mark, after, dark);
    canvas.restore();
  }

  Color _toInk(Color color, double dark) => Color.lerp(color, _ink, dark)!;

  void _paintMark(Canvas canvas, double mark, double after, double dark) {
    canvas.save();
    canvas.scale(mark / 512);
    canvas.translate(-256, -256);
    final glowing = dark < 1;

    // Sound rings thrown off the ear cups as they snap on.
    final ringTime = _span(after, 0.62, 1.42);
    if (ringTime > 0 && ringTime < 1 && glowing) {
      for (final (i, delay) in const [(0, 0.0), (1, 0.16)]) {
        final local = ((ringTime - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (local <= 0) continue;
        final ease = Curves.easeOutCubic.transform(local);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 12 * (1 - local) + 1
          ..color = _lime.withValues(alpha: (1 - local) * (i == 0 ? 0.85 : 0.55) * (1 - dark));
        final reach = 60 + ease * 170;
        canvas.drawArc(Rect.fromCircle(center: const Offset(89, 286), radius: reach), pi - 0.8, 1.6, false, paint);
        canvas.drawArc(Rect.fromCircle(center: const Offset(423, 286), radius: reach), -0.8, 1.6, false, paint);
      }
    }

    // The headband draws itself out from the top in both directions.
    final bandTime = Curves.easeOutCubic.transform(_span(after, 0.14, 0.62));
    if (bandTime > 0) {
      final left = Path()
        ..moveTo(256, 52)
        ..arcToPoint(const Offset(84, 224), radius: const Radius.circular(172), clockwise: false)
        ..lineTo(84, 262);
      final right = Path()
        ..moveTo(256, 52)
        ..arcToPoint(const Offset(428, 224), radius: const Radius.circular(172))
        ..lineTo(428, 262);
      final band = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 36
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_toInk(Colors.white, dark), _toInk(_lime, dark)],
        ).createShader(const Rect.fromLTWH(60, 40, 400, 240));
      final glow = glowing
          ? (Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 46
            ..color = _lime.withValues(alpha: 0.5 * (1 - dark))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26))
          : null;
      for (final side in [left, right]) {
        final metric = side.computeMetrics().first;
        final drawn = metric.extractPath(0, metric.length * bandTime);
        if (glow != null) canvas.drawPath(drawn, glow);
        canvas.drawPath(drawn, band);
        // A bright spark runs along the drawing tip.
        if (bandTime < 1) {
          final tip = metric.getTangentForOffset(metric.length * bandTime)?.position;
          if (tip != null) {
            canvas.drawCircle(tip, 24, Paint()..color = Colors.white..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
          }
        }
      }
    }

    // Ear cups snap in from the sides as the band reaches them.
    final cupTime = _span(after, 0.5, 0.76);
    if (cupTime > 0) {
      final pop = Curves.easeOutBack.transform(cupTime);
      for (final (x, dir) in const [(62.0, -1.0), (396.0, 1.0)]) {
        final cup = RRect.fromRectAndRadius(Rect.fromLTWH(x + dir * (1 - pop) * 90, 228, 54, 116), const Radius.circular(27));
        if (glowing) {
          canvas.drawRRect(cup, Paint()..color = _lime.withValues(alpha: 0.55 * cupTime * (1 - dark))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
        }
        canvas.drawRRect(cup, Paint()..color = _toInk(Color.lerp(Colors.white, _lime, cupTime)!, dark));
      }
    }

    // The V slams in on the impact, overshooting and burning down from white.
    final slam = _span(after, 0, 0.3);
    final scale = 2.7 - 1.7 * Curves.easeOutBack.transform(slam);
    canvas.save();
    canvas.translate(263, 298);
    canvas.scale(scale);
    canvas.translate(-263, -298);
    final v = Path()
      ..moveTo(170, 188)
      ..relativeLineTo(70, 0)
      ..relativeLineTo(20, 106)
      ..relativeLineTo(70, -106)
      ..relativeLineTo(46, 0)
      ..lineTo(282, 386)
      ..relativeCubicTo(-8, 14, -20, 22, -34, 22)
      ..relativeLineTo(-30, 0)
      ..relativeCubicTo(-10, 0, -18, -6, -20, -16)
      ..close();
    final heat = 1 - _span(after, 0.08, 0.7);
    if (glowing) {
      canvas.drawPath(v, Paint()..color = _green.withValues(alpha: (0.45 + heat * 0.5) * (1 - dark))..maskFilter = MaskFilter.blur(BlurStyle.normal, 30 + heat * 30));
    }
    canvas.drawPath(
      v,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_toInk(Color.lerp(_lime, Colors.white, heat)!, dark), _toInk(Color.lerp(_green, Colors.white, heat)!, dark)],
        ).createShader(const Rect.fromLTWH(170, 188, 206, 220)),
    );
    canvas.restore();
    canvas.restore();
  }

  void _paintName(Canvas canvas, double unit, double mark, double after, double dark) {
    final reveal = Curves.easeOutCubic.transform(_span(after, 0.72, 1.18));
    if (reveal <= 0) return;
    final width = unit * 0.68;
    final height = width / wordmarkAspect;
    final rise = (1 - reveal) * unit * 0.035;
    final box = Rect.fromCenter(center: Offset(0, mark * 0.62 + rise), width: width, height: height);
    final letters = _toInk(Colors.white, dark);
    // Light passes through the letters as they appear.
    final sweep = _span(after, 0.72, 1.45) * 1.5 - 0.25;
    final shader = LinearGradient(
      colors: [letters, letters, _toInk(_lime, dark), letters, letters.withValues(alpha: 0)],
      stops: [
        0,
        (sweep - 0.12).clamp(0.0, 1.0),
        sweep.clamp(0.0, 1.0),
        (sweep + 0.06).clamp(0.0, 1.0),
        (sweep + 0.14).clamp(0.0, 1.0),
      ],
    ).createShader(box);
    paintWordmark(canvas, box, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.t != t;
}
