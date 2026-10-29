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

class _Star {
  _Star(this.pos, this.speed, this.sway, this.phase);
  Offset pos;
  final double speed, sway, phase;
  bool caught = false;
  double caughtT = 0;
  Offset? from, to;
}

class _Popup {
  _Popup(this.text, this.pos, {this.big = false, this.sub});
  final String text;
  final String? sub;
  final Offset pos;
  final bool big;
  double age = 0;
}

/// Star Catch: slide Lumi along the lake and catch falling stars for 45
/// seconds. Five in a row builds a combo; caught stars join a
/// constellation in the sky.
class StarCatchGame extends StatefulWidget {
  const StarCatchGame({super.key, required this.brain});
  final LumiBrain brain;

  @override
  State<StarCatchGame> createState() => _StarCatchGameState();
}

class _StarCatchGameState extends State<StarCatchGame> {
  static const length = 45.0;
  final scene = Scene();
  final frame = ValueNotifier(0);
  final rnd = math.Random();
  LumiRig? rig;
  ScreenSpace? space;
  Size size = Size.zero;

  double countdown = 3.4;
  double t = 0;
  bool paused = false;
  bool over = false;
  int score = 0;
  int streak = 0;
  int caughtCount = 0;
  double lumiX = 0, lumiVX = 0;
  double? fingerX;
  double spawnT = 0.4;
  final stars = <_Star>[];
  final sky = <Offset>[]; // constellation of caught stars
  final popups = <_Popup>[];
  final flashes = <_Popup>[]; // catch flashes: where and how old

  int get multiplier => 1 + streak ~/ 5;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    await Scene.initializeStaticResources();
    // Lumi glows over the painted lake: see LumiBrain.glowSettings.
    scene.environmentSettings = LumiBrain.glowSettings();
    scene.add(LumiBrain.backdrop());
    final r = await widget.brain.makeRig();
    r.showUmbrella = false;
    r.root.scale = vm.Vector3.all(0.55);
    scene.add(r.root);
    if (mounted) setState(() => rig = r);
  }

  double get waterY => size.height * 0.66;
  Offset get lumiHead => Offset(lumiX, size.height * 0.74 - 40);

  void _tick(double dt) {
    final s = space;
    final r = rig;
    if (s == null || r == null) return;
    dt = dt.clamp(0, 0.1);
    if (lumiX == 0) lumiX = size.width / 2;
    if (paused) {
      r.update(0);
      return;
    }

    if (countdown > 0) {
      countdown -= dt;
    } else if (!over) {
      t += dt;
      if (t >= length) {
        t = length;
        over = true;
        widget.brain.stars += score;
        setState(() {});
      }
      // spawn
      spawnT -= dt;
      if (spawnT <= 0) {
        spawnT = math.max(0.35, 0.95 - t / length * 0.5) * (0.7 + rnd.nextDouble() * 0.6);
        stars.add(
          _Star(
            Offset(30 + rnd.nextDouble() * (size.width - 60), -20),
            150 + rnd.nextDouble() * 110 + t * 2.5,
            10 + rnd.nextDouble() * 18,
            rnd.nextDouble() * 6,
          ),
        );
      }
    }

    // Lumi follows the finger
    if (fingerX != null) {
      final acc = (fingerX! - lumiX) * 60 - lumiVX * 12;
      lumiVX += acc * dt;
    } else {
      lumiVX *= math.exp(-dt * 4);
    }
    lumiX = (lumiX + lumiVX * dt).clamp(30, size.width - 30);

    // stars
    final head = lumiHead;
    for (final st in stars) {
      if (st.caught) {
        st.caughtT += dt;
        final f = Curves.easeInOutCubic.transform((st.caughtT / 0.7).clamp(0, 1));
        st.pos = Offset.lerp(st.from, st.to, f)! + Offset(0, -math.sin(f * math.pi) * 60);
        continue;
      }
      st.pos = Offset(st.pos.dx + math.sin(t * 2 + st.phase) * st.sway * dt, st.pos.dy + st.speed * dt);
      if ((st.pos - head).distance < 46) {
        st.caught = true;
        st.from = st.pos;
        streak++;
        caughtCount++;
        final gain = multiplier;
        score += gain;
        final to = Offset(
          40 + rnd.nextDouble() * (size.width - 80),
          90 + rnd.nextDouble() * size.height * 0.22,
        );
        st.to = to;
        popups.add(_Popup('+$gain', st.pos));
        flashes.add(_Popup('', st.pos));
        if (streak % 5 == 0) {
          popups.add(
            _Popup(
              '×$multiplier COMBO',
              Offset(size.width / 2, size.height * 0.22),
              big: true,
              sub: '$streak in a row',
            ),
          );
        }
        r.squashY = 0.85;
        Future.delayed(const Duration(milliseconds: 120), () => r.squashY = 1.1);
        Future.delayed(const Duration(milliseconds: 260), () => r.squashY = 1);
      } else if (st.pos.dy > waterY + 60) {
        st.caught = true; // retire it
        st.caughtT = 99;
        if (streak >= 3) popups.add(_Popup('Combo lost', Offset(head.dx, head.dy - 70)));
        streak = 0;
      }
    }
    for (final st in stars.where((e) => e.caught && e.caughtT >= 0.7 && e.caughtT < 99)) {
      sky.add(st.to!);
      st.caughtT = 100;
    }
    stars.removeWhere((e) => e.caughtT >= 99);
    if (sky.length > 40) sky.removeRange(0, sky.length - 40);
    for (final p in popups) {
      p.age += dt;
    }
    popups.removeWhere((p) => p.age > (p.big ? 1.6 : 0.9));
    for (final f in flashes) {
      f.age += dt;
    }
    flashes.removeWhere((f) => f.age > 0.5);

    // place Lumi on the lily pad
    final world = s.toWorld(Offset(lumiX, size.height * 0.74));
    r.root.position = world + vm.Vector3(0, math.sin(t * 3) * 0.03, 0);
    r.tilt = (-lumiVX / 900).clamp(-0.35, 0.35);
    r.face = streak >= 5 ? Face.happy : Face.idle;
    r.handsUp = streak >= 5 ? 1 : 0;
    // look at the nearest falling star
    _Star? near;
    for (final st in stars) {
      if (st.caught) continue;
      if (near == null || (st.pos - head).distance < (near.pos - head).distance) near = st;
    }
    if (near != null) {
      final d = near.pos - head;
      r.gaze = vm.Vector2((d.dx / 200).clamp(-1, 1), (d.dy / 250).clamp(-1, 1));
    }
    r.update(dt);
    frame.value++;
  }

  void _restart() {
    setState(() {
      countdown = 3.4;
      t = 0;
      over = false;
      score = 0;
      streak = 0;
      caughtCount = 0;
      stars.clear();
      sky.clear();
      popups.clear();
      flashes.clear();
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
      backgroundColor: const Color(0xFF1A1240),
      body: LayoutBuilder(
        builder: (context, c) {
          size = Size(c.maxWidth, c.maxHeight);
          if (space?.size != size) space = ScreenSpace(size);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => fingerX = d.localPosition.dx,
            onPanUpdate: (d) => fingerX = d.localPosition.dx,
            onPanEnd: (_) => fingerX = null,
            onPanCancel: () => fingerX = null,
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _LakePainter(this, frame))),
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
                  child: IgnorePointer(child: CustomPaint(painter: _StarsPainter(this, frame))),
                ),
                ValueListenableBuilder(
                  valueListenable: frame,
                  builder: (_, _, _) => GameHud(
                    left: Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 15, color: Pd.gold),
                        const SizedBox(width: 3),
                        Text('$score', style: Pd.t(13, w: FontWeight.w700)),
                      ],
                    ),
                    center: Text(
                      '${(length - t).ceil() ~/ 60}:${((length - t).ceil() % 60).toString().padLeft(2, '0')}',
                      style: Pd.t(12.5, w: FontWeight.w700),
                    ),
                    meter: 1 - t / length,
                    paused: paused,
                    onPause: () => setState(() => paused = !paused),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: frame,
                  builder: (_, _, _) => countdown > 0
                      ? GameCountdown(value: countdown, hint: 'Slide to move. Catch the falling stars!')
                      : const SizedBox.shrink(),
                ),
                if (over)
                  GameOverCard(
                    title: 'Time!',
                    lines: ['$caughtCount stars caught', '+$score stars for the wardrobe'],
                    onAgain: _restart,
                    onDone: () => Navigator.pop(context),
                  ),
                if (paused && !over)
                  GamePausedCard(
                    onResume: () => setState(() => paused = false),
                    onQuit: () => Navigator.pop(context),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LakePainter extends CustomPainter {
  _LakePainter(this.g, Listenable r) : super(repaint: r);
  final _StarCatchGameState g;

  @override
  void paint(Canvas canvas, Size size) {
    final wy = g.waterY;
    final sky = Rect.fromLTRB(0, 0, size.width, wy);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1A66), Color(0xFF5B3A9E), Color(0xFF9B6CC8)],
          stops: [0, 0.7, 1],
        ).createShader(sky),
    );
    final rnd = math.Random(3);
    final tw = g.t;
    for (var i = 0; i < 90; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * wy * 0.9);
      final a = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(tw * 2 + i));
      canvas.drawCircle(p, 0.6 + rnd.nextDouble() * 0.8, Paint()..color = Colors.white.withValues(alpha: a));
    }
    // hills
    final hills = Path()..moveTo(0, wy);
    for (var x = 0.0; x <= size.width; x += 8) {
      final h = 30 + 26 * math.sin(x / size.width * 5.2 + 1) + 14 * math.sin(x / size.width * 13);
      hills.lineTo(x, wy - h);
    }
    hills
      ..lineTo(size.width, wy)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0xFF1E1440));
    // water
    final water = Rect.fromLTRB(0, wy, size.width, size.height);
    canvas.drawRect(
      water,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6B4BA8), Color(0xFF2A1C5C), Color(0xFF140E33)],
          stops: [0, 0.3, 1],
        ).createShader(water),
    );
    // shimmering ripples
    final rip = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    for (var i = 0; i < 26; i++) {
      final y = wy + 8 + i * i * 0.55;
      if (y > size.height) break;
      final x = (rnd.nextDouble() * size.width + tw * (10 + i)) % size.width;
      canvas.drawLine(Offset(x, y), Offset(x + 18 + i * 1.5, y), rip);
    }
    // the hills mirrored in the still water, fading with depth
    canvas.save();
    canvas.translate(0, 2 * wy);
    canvas.scale(1, -1);
    canvas.drawPath(
      hills,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: const [Color(0xCC1E1440), Color(0x001E1440)],
        ).createShader(Rect.fromLTRB(0, wy - 70, size.width, wy)),
    );
    canvas.restore();
    // Lumi's lily pad, and Lumi's light smeared down the water under it
    final px = g.lumiX == 0 ? size.width / 2 : g.lumiX;
    final pad = Offset(px, size.height * 0.74 + 92);
    final glow = Paint()..blendMode = BlendMode.plus;
    final smear = Rect.fromCenter(center: pad + const Offset(0, 62), width: 46, height: 110);
    canvas.drawOval(
      smear,
      glow
        ..shader = const RadialGradient(
          colors: [Color(0x665EA8FF), Color(0x225EA8FF), Color(0x005EA8FF)],
        ).createShader(smear),
    );
    for (var i = 0; i < 5; i++) {
      final y = pad.dy + 22 + i * 13.0;
      final w = 30 - i * 3 + math.sin(tw * 3 + i) * 4;
      canvas.drawLine(
        Offset(px - w / 2, y),
        Offset(px + w / 2, y),
        Paint()
          ..color = Color.fromRGBO(140, 200, 255, 0.35 - i * 0.05)
          ..strokeWidth = 3
          ..blendMode = BlendMode.plus,
      );
    }
    canvas.drawCircle(
      pad + const Offset(0, 74),
      5,
      Paint()
        ..color = const Color(0x88FF9A50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final padRect = Rect.fromCenter(center: pad, width: 86, height: 18);
    canvas.drawOval(padRect.shift(const Offset(0, 3)), Paint()..color = const Color(0xFF123A26));
    canvas.drawOval(
      padRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5FC48A), Color(0xFF2E8A55)],
        ).createShader(padRect),
    );
    // reflection of the constellation
    final refl = Paint()..color = const Color(0x33FFE08A);
    for (final s in g.sky) {
      canvas.drawCircle(Offset(s.dx, 2 * wy - s.dy * 0.6 - wy * 0.4), 1.6, refl);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.g, Listenable r) : super(repaint: r);
  final _StarCatchGameState g;

  @override
  void paint(Canvas canvas, Size size) {
    // constellation lines
    final line = Paint()
      ..color = const Color(0x88FFE6A8)
      ..strokeWidth = 1;
    for (var i = 1; i < g.sky.length; i++) {
      if ((g.sky[i] - g.sky[i - 1]).distance < 160) canvas.drawLine(g.sky[i - 1], g.sky[i], line);
    }
    for (final s in g.sky) {
      drawStar(canvas, s, 5, const Color(0xFFFFE08A));
    }
    final add = Paint()..blendMode = BlendMode.plus;
    for (final st in g.stars) {
      // a long thin falling trail, brightest at the star
      if (!st.caught) {
        const len = 110.0;
        canvas.drawLine(
          st.pos - const Offset(0, len),
          st.pos,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0x00FFE7A0), const Color(0xAAFFE7A0)],
            ).createShader(Rect.fromPoints(st.pos - const Offset(1, len), st.pos))
            ..strokeWidth = 1.3
            ..blendMode = BlendMode.plus,
        );
      }
      final r = st.caught ? 8.0 : 13.0;
      canvas.drawCircle(
        st.pos,
        r * 2.6,
        add
          ..shader = RadialGradient(
            colors: const [Color(0x88FFD98A), Color(0x22FFB84D), Color(0x00FFB84D)],
          ).createShader(Rect.fromCircle(center: st.pos, radius: r * 2.6)),
      );
      add.shader = null;
      drawStar(canvas, st.pos, r, const Color(0xFFFFE6A0));
    }
    // catch flashes: a white-hot burst with a four-point glint and a ring
    for (final f in g.flashes) {
      final k = f.age / 0.5;
      final a = (1 - k).clamp(0.0, 1.0);
      final rr = 18 + k * 50;
      canvas.drawCircle(
        f.pos,
        rr,
        add
          ..shader = RadialGradient(
            colors: [
              Color.fromRGBO(255, 250, 230, 0.9 * a),
              Color.fromRGBO(255, 210, 120, 0.35 * a),
              const Color(0x00FFD278),
            ],
          ).createShader(Rect.fromCircle(center: f.pos, radius: rr)),
      );
      add.shader = null;
      final glint = Paint()
        ..color = Color.fromRGBO(255, 245, 220, 0.8 * a)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus;
      final l = 30 + k * 40;
      canvas.drawLine(f.pos - Offset(l, 0), f.pos + Offset(l, 0), glint);
      canvas.drawLine(f.pos - Offset(0, l * 0.6), f.pos + Offset(0, l * 0.6), glint);
      canvas.drawCircle(
        f.pos,
        12 + k * 34,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * a
          ..color = Color.fromRGBO(255, 220, 150, 0.7 * a)
          ..blendMode = BlendMode.plus,
      );
    }
    for (final p in g.popups) {
      final f = p.age / (p.big ? 1.6 : 0.9);
      final a = (1 - f).clamp(0.0, 1.0);
      final tp = TextPainter(
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            TextSpan(
              text: p.text,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: p.big ? 30 : 16,
                fontWeight: FontWeight.w800,
                letterSpacing: p.big ? 1.5 : 0,
                color: Colors.white.withValues(alpha: a),
                shadows: const [Shadow(color: Color(0xAAFFC34D), blurRadius: 14)],
              ),
            ),
            if (p.sub != null)
              TextSpan(
                text: '\n${p.sub}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: const Color(0xFFD6B8FF).withValues(alpha: a),
                ),
              ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p.pos - Offset(tp.width / 2, tp.height / 2 + f * 30));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void drawStar(Canvas canvas, Offset c, double r, Color col) {
  canvas.drawCircle(
    c,
    r * 2.2,
    Paint()
      ..color = col.withValues(alpha: 0.28)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.9),
  );
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final rr = i.isEven ? r : r * 0.45;
    final p = c + Offset(math.cos(a), math.sin(a)) * rr;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(path..close(), Paint()..color = col);
}
