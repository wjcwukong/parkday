import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import '../lumi/lumi_brain.dart';
import '../scene/lumi_rig.dart';
import '../scene/space.dart';
import '../theme.dart';
import '../widgets/light_layer.dart';
import 'game_hud.dart';
import 'star_catch.dart' show drawStar;

const _ppm = 3.0; // screen pixels per meter of altitude
const _moonAlt = 1000.0;

class _Pickup {
  _Pickup(this.x, this.alt, this.ring);
  final double x; // 0..1 across the screen
  final double alt;
  final bool ring;
  bool taken = false;
  double takenT = 0;
}

class _Pop {
  _Pop(this.text, this.alt, this.x);
  final String text;
  final double alt, x;
  double age = 0;
}

/// Sky Lift: hold to float up, slide to steer. Fly through rings, grab
/// stars for lantern fuel, and see if Lumi can reach the moon.
class SkyLiftGame extends StatefulWidget {
  const SkyLiftGame({super.key, required this.brain, required this.onBest});
  final LumiBrain brain;
  final ValueChanged<int> onBest;

  @override
  State<SkyLiftGame> createState() => _SkyLiftGameState();
}

class _SkyLiftGameState extends State<SkyLiftGame> {
  final scene = Scene();
  final frame = ValueNotifier(0);
  LumiRig? rig;
  ScreenSpace? space;
  Size size = Size.zero;

  double countdown = 3.4;
  double t = 0;
  double alt = 0, vy = 0, maxAlt = 0;
  double x = 0.5, vx = 0;
  double fuel = 1;
  bool holding = false;
  double? fingerX;
  bool paused = false, over = false, moon = false;
  double moonT = 0;
  int starsGot = 0, rings = 0, bonus = 0;
  final pickups = <_Pickup>[];
  final pops = <_Pop>[];
  double _generated = 0;
  final rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    await Scene.initializeStaticResources();
    // Lumi glows over the painted sky: see LumiBrain.glowSettings.
    scene.environmentSettings = LumiBrain.glowSettings();
    scene.add(LumiBrain.backdrop());
    final r = await widget.brain.makeRig();
    r.showUmbrella = false;
    r.root.scale = vm.Vector3.all(0.68);
    scene.add(r.root);
    if (mounted) setState(() => rig = r);
  }

  double get lumiY => size.height * 0.6;
  double screenYFor(double a) => lumiY - (a - alt) * _ppm;

  void _generate(double upTo) {
    while (_generated < upTo) {
      _generated += 30;
      final a = _generated;
      if (a % 90 == 0) {
        pickups.add(_Pickup(0.2 + rnd.nextDouble() * 0.6, a, true));
      } else {
        pickups.add(_Pickup(0.1 + rnd.nextDouble() * 0.8, a + rnd.nextDouble() * 20, false));
      }
    }
  }

  void _tick(double dt) {
    final r = rig;
    final s = space;
    if (r == null || s == null) return;
    dt = dt.clamp(0, 0.1);
    if (paused) {
      r.update(0);
      return;
    }
    if (countdown > 0) {
      countdown -= dt;
    } else if (!over) {
      t += dt;
      final thrust = holding && fuel > 0;
      vy += (thrust ? 30.0 : 0) * dt - 15 * dt;
      vy = vy.clamp(-34, 42);
      if (thrust) fuel = math.max(0, fuel - dt * 0.085);
      alt = math.max(0, alt + vy * dt);
      if (alt == 0 && vy < 0) vy = 0;
      maxAlt = math.max(maxAlt, alt);
      if (maxAlt > 20 && alt <= 0.1) {
        over = true;
        widget.onBest(maxAlt.round());
        widget.brain.stars += starsGot;
        setState(() {});
      }
      if (fuel <= 0 && alt <= 0.1 && t > 1) {
        over = true;
        widget.onBest(maxAlt.round());
        setState(() {});
      }
      // steering
      if (fingerX != null) {
        final target = (fingerX! / size.width).clamp(0.06, 0.94);
        vx += ((target - x) * 30 - vx * 7) * dt;
      } else {
        vx *= math.exp(-dt * 3);
      }
      x = (x + vx * dt).clamp(0.06, 0.94);
      _generate(alt + 400);

      // pickups
      final lumi = Offset(x * size.width, lumiY);
      for (final p in pickups) {
        if (p.taken) {
          p.takenT += dt;
          continue;
        }
        final pos = Offset(p.x * size.width, screenYFor(p.alt));
        final d = (pos - lumi).distance;
        if (p.ring ? d < 38 : d < 34) {
          p.taken = true;
          if (p.ring) {
            rings++;
            bonus += 25;
            fuel = math.min(1, fuel + 0.22);
            pops.add(_Pop('+25', p.alt, p.x));
          } else {
            starsGot++;
            fuel = math.min(1, fuel + 0.1);
            pops.add(_Pop('+1', p.alt, p.x));
          }
        }
      }
      pickups.removeWhere((p) => p.alt < alt - 200 || p.takenT > 0.6);
      if (!moon && alt >= _moonAlt) {
        moon = true;
        moonT = 0;
        starsGot += 10;
      }
    }
    if (moon) moonT += dt;
    for (final p in pops) {
      p.age += dt;
    }
    pops.removeWhere((p) => p.age > 0.9);

    final world = s.toWorld(Offset(x * size.width, lumiY));
    r.root.position = world;
    r.squashY = holding && fuel > 0 ? 1.08 : 0.97;
    r.tilt = (-vx * 1.6).clamp(-0.4, 0.4);
    r.handsUp = holding && fuel > 0 ? 1 : 0;
    r.face = moon && moonT < 4 ? Face.happy : (vy < -18 ? Face.surprised : Face.idle);
    r.gaze = vm.Vector2(0, -0.8);
    r.glow = 0.9 + fuel * 0.3;
    r.update(dt);
    frame.value++;
  }

  void _restart() {
    setState(() {
      countdown = 3.4;
      t = 0;
      alt = 0;
      vy = 0;
      maxAlt = 0;
      x = 0.5;
      vx = 0;
      fuel = 1;
      over = false;
      moon = false;
      starsGot = 0;
      rings = 0;
      bonus = 0;
      pickups.clear();
      pops.clear();
      _generated = 0;
    });
  }

  @override
  void dispose() {
    frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6B3D6),
      body: LayoutBuilder(
        builder: (context, c) {
          size = Size(c.maxWidth, c.maxHeight);
          if (space?.size != size) space = ScreenSpace(size);
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              holding = true;
              fingerX = e.localPosition.dx;
            },
            onPointerMove: (e) => fingerX = e.localPosition.dx,
            onPointerUp: (_) {
              holding = false;
              fingerX = null;
            },
            onPointerCancel: (_) {
              holding = false;
              fingerX = null;
            },
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _SkyPainter(this, frame, front: false))),
                Positioned.fill(child: CustomPaint(painter: LumiShadePainter(() => rig, () => space, frame))),
                if (rig != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: LightLayer(
                        child: SceneView(scene, camera: space!.camera, onTick: (_, dt) => _tick(dt)),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _SkyPainter(this, frame, front: true))),
                ),
                ValueListenableBuilder(
                  valueListenable: frame,
                  builder: (_, _, _) => GameHud(
                    left: Text('↑ ${alt.round()} m', style: Pd.t(12.5, w: FontWeight.w700)),
                    center: Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Colors.white),
                        Text(' $starsGot', style: Pd.t(12, w: FontWeight.w700)),
                        const SizedBox(width: 8),
                        const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                        Text(' $rings', style: Pd.t(12, w: FontWeight.w700)),
                      ],
                    ),
                    meter: fuel,
                    paused: paused,
                    onPause: () => setState(() => paused = !paused),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: frame,
                  builder: (_, _, _) => countdown > 0
                      ? GameCountdown(value: countdown, hint: 'Hold to float up. Slide to steer.')
                      : const SizedBox.shrink(),
                ),
                if (over)
                  GameOverCard(
                    title: moon ? 'Moonwalker!' : '${maxAlt.round()} m',
                    lines: [
                      moon ? 'Lumi reached the moon at ${maxAlt.round()} m' : 'Lumi floated back down',
                      '$starsGot ${starsGot == 1 ? "star" : "stars"} · $rings rings (+$bonus)',
                    ],
                    onAgain: _restart,
                    onDone: () => Navigator.pop(context),
                  ),
                if (paused && !over)
                  GamePausedCard(onResume: () => setState(() => paused = false), onQuit: () => Navigator.pop(context)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.g, Listenable r, {required this.front}) : super(repaint: r);
  final _SkyLiftGameState g;
  final bool front;

  static Color _lerp3(Color a, Color b, Color c, double f) =>
      f < 0.5 ? Color.lerp(a, b, f * 2)! : Color.lerp(b, c, (f - 0.5) * 2)!;

  @override
  void paint(Canvas canvas, Size size) {
    final f = (g.alt / _moonAlt).clamp(0.0, 1.0);
    if (!front) {
      final top = _lerp3(const Color(0xFFE7A9CF), const Color(0xFF9A72C9), const Color(0xFF2A1C62), f);
      final bottom = _lerp3(const Color(0xFFFFD6C2), const Color(0xFFDDA8D9), const Color(0xFF5A3A9A), f);
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ).createShader(rect),
      );
      // stars fade in with altitude
      if (f > 0.35) {
        final rnd = math.Random(8);
        for (var i = 0; i < 80; i++) {
          final p = Offset(rnd.nextDouble() * size.width, (rnd.nextDouble() * size.height + g.alt * 0.3) % size.height);
          canvas.drawCircle(
            p,
            0.6 + rnd.nextDouble(),
            Paint()..color = Colors.white.withValues(alpha: (f - 0.35) * 1.2 * rnd.nextDouble()),
          );
        }
      }
      final my = g.screenYFor(_moonAlt + 70);
      if (my > -300) {
        final mc = Offset(size.width * 0.5, my);
        canvas.drawCircle(
          mc,
          200,
          Paint()
            ..shader = RadialGradient(colors: [const Color(0x66FFF6E0), const Color(0x00FFF6E0)])
                .createShader(Rect.fromCircle(center: mc, radius: 200)),
        );
        canvas.drawCircle(mc, 112, Paint()..color = const Color(0xFFFFF6E3));
        canvas.drawCircle(mc + const Offset(-30, -20), 18, Paint()..color = const Color(0x22B8A88A));
        canvas.drawCircle(mc + const Offset(36, 28), 26, Paint()..color = const Color(0x1AB8A88A));
      }
      // Ground: the park far below, sunk in a warm sunset haze that fades
      // up into the sky rather than a hard horizon, with its lanterns
      // twinkling through.
      final gy = g.screenYFor(-30);
      if (gy < size.height + 40) {
        final haze = Rect.fromLTRB(0, gy - 140, size.width, size.height + 50);
        canvas.drawRect(
          haze,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bottom.withValues(alpha: 0), const Color(0xFFFFC7A8), const Color(0xFF7A4A72)],
              stops: [0, 140 / haze.height, 1],
            ).createShader(haze),
        );
        final rnd = math.Random(2);
        for (var i = 0; i < 30; i++) {
          final p = Offset(rnd.nextDouble() * size.width, gy + 20 + rnd.nextDouble() * 160);
          canvas.drawCircle(
            p,
            5,
            Paint()
              ..blendMode = BlendMode.plus
              ..shader = RadialGradient(colors: [const Color(0x88FFE2A8), const Color(0x00FFE2A8)])
                  .createShader(Rect.fromCircle(center: p, radius: 5)),
          );
        }
      }
    }

    // Lumi's lantern trail while it climbs: a hot streak of light below it
    if (!front && g.vy > 2) {
      final k = (g.vy / 42).clamp(0.0, 1.0);
      final base = Offset(g.x * size.width, g.lumiY + 70);
      final len = 60 + 170 * k;
      final rect = Rect.fromLTWH(base.dx - 11, base.dy, 22, len);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(11)),
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromRGBO(255, 236, 200, 0.75 * k),
              Color.fromRGBO(255, 160, 90, 0.35 * k),
              const Color(0x00FF8A50),
            ],
            stops: const [0, 0.35, 1],
          ).createShader(rect),
      );
      canvas.drawCircle(
        base,
        26,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(colors: [Color.fromRGBO(255, 220, 170, 0.6 * k), const Color(0x00FFB070)])
              .createShader(Rect.fromCircle(center: base, radius: 26)),
      );
    }

    // clouds: alternate layers behind and in front of Lumi
    final band0 = ((g.alt - size.height / _ppm) / 40).floor() - 1;
    final band1 = ((g.alt + size.height / _ppm) / 40).ceil() + 1;
    for (var b = math.max(0, band0); b <= band1; b++) {
      final rnd = math.Random(b * 31 + 7);
      for (var k = 0; k < 3; k++) {
        final isFront = rnd.nextDouble() < 0.3;
        final cx = rnd.nextDouble() * size.width;
        final ca = b * 40.0 + rnd.nextDouble() * 40;
        final scale = 0.7 + rnd.nextDouble() * 0.9;
        // Some are long banks of billows rather than single puffs.
        final wide = 1 + rnd.nextDouble() * rnd.nextDouble() * 1.6;
        if (isFront != front || (isFront && ca < 70)) continue;
        final y = g.screenYFor(ca) + (front ? 0 : 0);
        final drift = math.sin(g.t * 0.3 + b) * 14;
        final col = Color.lerp(
          const Color(0xFFEFCDE8),
          const Color(0xFFB79AE0),
          f,
        )!.withValues(alpha: front ? 0.94 : 1.0);
        _cloud(canvas, Offset(cx + drift, y), scale * (front ? 1.25 : 1), col, wide);
      }
    }

    // The moon, far off from the start: peeking out over the far clouds,
    // growing as Lumi climbs, with a soft halo of moonlight. The near moon
    // takes over at the top.
    if (!front) {
      final my = g.screenYFor(_moonAlt + 70);
      final far = ((-my - 300) / 300).clamp(0.0, 1.0);
      if (far > 0) {
        final fc = Offset(size.width * 0.7, size.height * (0.2 - 0.06 * f));
        final fr = 34 + 56 * f;
        final halo = Rect.fromCircle(center: fc, radius: fr * 3.4);
        canvas.drawCircle(
          fc,
          fr * 3.4,
          Paint()
            ..shader = RadialGradient(
              colors: [
                const Color(0xFFFFF3DA).withValues(alpha: 0.55 * far),
                const Color(0xFFFFD9C2).withValues(alpha: 0.18 * far),
                const Color(0x00FFD9C2),
              ],
              stops: const [0, 0.35, 1],
            ).createShader(halo),
        );
        canvas.drawCircle(fc, fr, Paint()..color = const Color(0xFFFFF6E6).withValues(alpha: far));
        canvas.drawCircle(
          fc + Offset(-0.3, -0.2) * fr,
          0.18 * fr,
          Paint()..color = Color.fromRGBO(184, 168, 150, 0.16 * far),
        );
        canvas.drawCircle(
          fc + Offset(0.28, 0.3) * fr,
          0.24 * fr,
          Paint()..color = Color.fromRGBO(184, 168, 150, 0.12 * far),
        );
      }
    }

    if (front) {
      for (final p in g.pickups) {
        final pos = Offset(p.x * size.width, g.screenYFor(p.alt));
        if (pos.dy < -60 || pos.dy > size.height + 60) continue;
        final fade = p.taken ? (1 - p.takenT / 0.6).clamp(0.0, 1.0) : 1.0;
        if (p.ring) {
          final double rr = 30.0 + (p.taken ? p.takenT * 40 : 0.0);
          canvas.drawCircle(
            pos,
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..color = const Color(0xFFFFF0B8).withValues(alpha: 0.9 * fade)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
          );
          canvas.drawCircle(
            pos,
            rr + 8,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 10
              ..color = const Color(0xFFFFC56B).withValues(alpha: 0.18 * fade),
          );
        } else if (!p.taken) {
          drawStar(canvas, pos, 9, const Color(0xFFFFE08A));
        }
      }
      for (final p in g.pops) {
        final tp = TextPainter(
          text: TextSpan(
            text: p.text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 1 - p.age / 0.9),
              shadows: const [Shadow(color: Color(0x88FF8FB1), blurRadius: 8)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(p.x * size.width + 20, g.screenYFor(p.alt) - 30 - p.age * 30));
      }
      if (g.moon && g.moonT < 6) {
        final double a = (g.moonT < 0.5 ? g.moonT / 0.5 : (g.moonT > 5 ? 6 - g.moonT : 1.0)).clamp(0.0, 1.0).toDouble();
        final tp = TextPainter(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'YOU REACHED THE\nMOON!',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.white.withValues(alpha: a),
                  shadows: const [Shadow(color: Color(0xAAFFC34D), blurRadius: 18)],
                ),
              ),
              TextSpan(
                text: '\nFireworks for you',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFFE3A8).withValues(alpha: a),
                ),
              ),
            ],
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width - 20);
        tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height * 0.18));
        // celebration bursts
        final rnd = math.Random(5);
        for (var k = 0; k < 5; k++) {
          final st = k * 0.8;
          final age = g.moonT - st;
          if (age < 0 || age > 1.6) continue;
          final c = Offset(size.width * (0.15 + rnd.nextDouble() * 0.7), size.height * (0.25 + rnd.nextDouble() * 0.3));
          final col = [const Color(0xFF9BE7FF), const Color(0xFFFF9BD2), const Color(0xFFFFE08A)][k % 3];
          for (var i = 0; i < 40; i++) {
            final ang = i / 40 * math.pi * 2;
            final rr = 70 * Curves.easeOutCubic.transform((age / 1.2).clamp(0, 1));
            canvas.drawCircle(
              c + Offset(math.cos(ang), math.sin(ang)) * rr + Offset(0, age * age * 12),
              1.8,
              Paint()..color = col.withValues(alpha: (1 - age / 1.6).clamp(0, 1)),
            );
          }
        }
      }
    }
  }

  /// A cumulus: a heap of puffs, each lit from the upper left and shaded
  /// lilac underneath, on a flat, darker base, so it reads as a soft 3D
  /// lump like the original's clouds rather than a flat cut-out.
  /// A cloud of overlapping billows, [wide] times as long as it is tall,
  /// lavender in the shade above and warmed from below by the sunset.
  void _cloud(Canvas canvas, Offset c, double s, Color col, [double wide = 1]) {
    final shadow = Color.lerp(col, const Color(0xFF7E62B8), 0.65)!;
    final light = Color.lerp(col, const Color(0xFFFFE6DA), 0.6)!;
    const puffs = [
      (-58.0, 14.0, 22.0),
      (58.0, 12.0, 24.0),
      (-30.0, 8.0, 30.0),
      (30.0, 4.0, 32.0),
      (-12.0, -14.0, 34.0),
      (20.0, -22.0, 30.0),
      (0.0, 16.0, 30.0),
    ];
    // the flat underside, catching the warm light
    final base = Rect.fromCenter(center: c + Offset(0, 26) * s, width: 150 * s * wide, height: 30 * s);
    canvas.drawOval(base, Paint()..color = light.withValues(alpha: light.a * 0.95));
    final copies = wide > 1.4 ? 2 : 1;
    for (var n = 0; n < copies; n++) {
      final shift = copies == 1 ? 0.0 : (n - 0.5) * 75 * (wide - 0.6);
      for (final (dx, dy, r) in puffs) {
        final pc = c + Offset(dx * (copies == 1 ? wide : 1) + shift, dy) * s;
        final rect = Rect.fromCircle(center: pc, radius: r * s);
        canvas.drawCircle(
          pc,
          r * s,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.25, 0.55),
              radius: 1.15,
              colors: [light, col, shadow],
              stops: const [0, 0.5, 1],
            ).createShader(rect),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
