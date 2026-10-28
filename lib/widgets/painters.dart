import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lumi/lumi_brain.dart';

/// Deep-night background with twinkling stars.
class StarfieldPainter extends CustomPainter {
  StarfieldPainter(this.t, {this.seed = 3, this.density = 1.0}) : super(repaint: t);
  final Animation<double> t;
  final int seed;
  final double density;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E2556), Color(0xFF131740), Color(0xFF0B0E28)],
          stops: [0, 0.45, 1],
        ).createShader(rect),
    );
    final rnd = math.Random(seed);
    final n = (size.width * size.height / 2600 * density).round();
    final time = t.value * 60;
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.35 + rnd.nextDouble() * 0.9;
      final ph = rnd.nextDouble() * 6.28;
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(time * (0.6 + rnd.nextDouble()) + ph));
      p.color = Colors.white.withValues(alpha: 0.55 * tw);
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter old) => false;
}

/// The 2D hearts and Zzz that float around Lumi (its sparkle bursts are 3D,
/// see `HomeFx`).
class LumiAuraPainter extends CustomPainter {
  LumiAuraPainter(this.brain, {this.front = false}) : super(repaint: brain.frame);
  final LumiBrain brain;
  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final rig = brain.rig;
    final space = brain.space;
    if (rig == null || space == null) return;
    if (front) _particles(canvas);
  }

  void _particles(Canvas canvas) {
    for (final (o, age) in brain.heartList) {
      final t = age / 1.4;
      final p = o + Offset(math.sin(age * 5) * 6, -age * 50);
      _heart(canvas, p, 7 + t * 3, const Color(0xFFFF8FB1).withValues(alpha: 1 - t));
    }
    for (final (o, age) in brain.zeds) {
      final t = age / 2.6;
      final p = o + Offset(age * 14 + math.sin(age * 2) * 6, -age * 26);
      final tp = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontSize: 12 + t * 10,
            color: Colors.white.withValues(alpha: (1 - t) * 0.9),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p);
    }
  }

  void _heart(Canvas canvas, Offset c, double s, Color col) {
    final path = Path()
      ..moveTo(c.dx, c.dy + s * 0.35)
      ..cubicTo(c.dx - s, c.dy - s * 0.3, c.dx - s * 0.45, c.dy - s, c.dx, c.dy - s * 0.45)
      ..cubicTo(c.dx + s * 0.45, c.dy - s, c.dx + s, c.dy - s * 0.3, c.dx, c.dy + s * 0.35);
    canvas.drawPath(path, Paint()..color = col);
  }

  @override
  bool shouldRepaint(covariant LumiAuraPainter old) => false;
}

/// Rain or snow falling through the header.
class WeatherPainter extends CustomPainter {
  WeatherPainter(this.t, this.weather) : super(repaint: t);
  final Animation<double> t;
  final Weather weather;

  @override
  void paint(Canvas canvas, Size size) {
    if (weather == Weather.clear) return;
    final rnd = math.Random(11);
    final time = t.value * 60;
    if (weather == Weather.rain) {
      final p = Paint()
        ..color = const Color(0x668FB8FF)
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 70; i++) {
        final x0 = rnd.nextDouble() * (size.width + 60);
        final sp = 380 + rnd.nextDouble() * 220;
        final y = (rnd.nextDouble() * size.height + time * sp) % (size.height + 40) - 20;
        final x = x0 - y * 0.12;
        canvas.drawLine(Offset(x, y), Offset(x - 2.2, y + 13), p);
      }
    } else {
      final p = Paint()..color = const Color(0xCCFFFFFF);
      for (var i = 0; i < 60; i++) {
        final x0 = rnd.nextDouble() * size.width;
        final sp = 22 + rnd.nextDouble() * 30;
        final y = (rnd.nextDouble() * size.height + time * sp) % (size.height + 10) - 5;
        final x = x0 + math.sin(time * 0.8 + i) * 12;
        canvas.drawCircle(Offset(x, y), 1 + rnd.nextDouble() * 1.6, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WeatherPainter old) => old.weather != weather;
}

/// The animated fireworks thumbnail on the "Tonight" card.
class FireworksThumbPainter extends CustomPainter {
  FireworksThumbPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3B2266), Color(0xFF6A3C8E), Color(0xFF2A1A4A)],
          stops: [0, 0.6, 1],
        ).createShader(rect),
    );
    final time = t.value * 60;
    // falling golden trails (willow)
    final rnd = math.Random(5);
    final trail = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final x = rnd.nextDouble() * size.width;
      final len = 14 + rnd.nextDouble() * 26;
      final sp = 18 + rnd.nextDouble() * 22;
      final y = (rnd.nextDouble() * size.height + time * sp) % (size.height + len);
      trail
        ..strokeWidth = 0.8
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0x00FFD9A0), const Color(0xAAFFD9A0)],
        ).createShader(Rect.fromLTWH(x, y - len, 1, len));
      canvas.drawLine(Offset(x, y - len), Offset(x, y), trail);
    }
    // peony burst
    _burst(canvas, Offset(size.width * 0.45, size.height * 0.36), 34, time, 0, const [
      Color(0xFFFF9BD2),
      Color(0xFFFFFFFF),
      Color(0xFF9BE7FF),
    ]);
    // ring burst
    final rc = Offset(size.width * 0.72, size.height * 0.24);
    final ringPaint = Paint()
      ..color = const Color(0xFFD7A6FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    final rp = (time * 0.35) % 1;
    canvas.drawOval(Rect.fromCenter(center: rc, width: 26 + rp * 6, height: 20 + rp * 5), ringPaint);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
          stops: const [0.45, 1],
        ).createShader(rect),
    );
  }

  void _burst(Canvas canvas, Offset c, double r, double time, int seed, List<Color> cols) {
    final rnd = math.Random(seed + 9);
    final pulse = 0.85 + 0.15 * math.sin(time * 1.5);
    for (var i = 0; i < 70; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final rr = r * (0.25 + rnd.nextDouble() * 0.75) * pulse;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      final col = cols[i % cols.length];
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * rr * 0.7,
        p,
        Paint()
          ..color = col.withValues(alpha: 0.7)
          ..strokeWidth = 0.8,
      );
      canvas.drawCircle(p, 0.9, Paint()..color = col);
    }
    canvas.drawCircle(
      c,
      8,
      Paint()
        ..color = const Color(0x88FFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(covariant FireworksThumbPainter old) => false;
}
