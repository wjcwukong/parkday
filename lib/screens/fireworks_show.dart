import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../lumi/lumi_brain.dart';
import '../scene/lumi_rig.dart';
import '../scene/space.dart';
import '../theme.dart';

const _showLength = 60.0;

class _Chapter {
  const _Chapter(this.name, this.start, this.eye, this.target);
  final String name;
  final double start;
  final List<double> eye;
  final List<double> target;
}

const _chapters = [
  _Chapter('first break', 0, [0.2, 1.9, -5.5], [0.0, 12.0, 60.0]),
  _Chapter('close-up', 12, [1.3, 1.9, -2.6], [0.0, 3.4, 10.0]),
  _Chapter('build', 22, [-0.6, 3.2, -9.0], [0.0, 12.0, 60.0]),
  _Chapter('finale', 38, [-2.4, 4.6, -11.0], [0.0, 15.0, 70.0]),
  _Chapter('afterglow', 52, [0.0, 2.4, -3.6], [0.0, 6.0, 40.0]),
];

enum _Kind { peony, ring, willow, palm, glitter }

/// One shell of the show. Everything about it is a pure function of time so
/// the timeline can be scrubbed freely.
class _Shell {
  _Shell(this.launch, this.x, this.z, this.height, this.kind, this.colors, this.seed, {this.scale = 1});
  final double launch;
  final double x, z, height;
  final _Kind kind;
  final List<Color> colors;
  final int seed;
  final double scale;
  static const rise = 1.5;
  double get burst => launch + rise;
  double get life => kind == _Kind.willow ? 4.6 : (kind == _Kind.glitter ? 3.2 : 2.6);
  late final List<vm.Vector3> dirs = _dirs();

  List<vm.Vector3> _dirs() {
    final rnd = math.Random(seed);
    final out = <vm.Vector3>[];
    switch (kind) {
      case _Kind.ring:
        final tilt = rnd.nextDouble() * 0.9 - 0.45;
        final yaw = rnd.nextDouble() * math.pi;
        for (var i = 0; i < 64; i++) {
          final a = i / 64 * math.pi * 2;
          var v = vm.Vector3(math.cos(a), math.sin(a), 0);
          v = vm.Quaternion.euler(yaw, tilt, 0).rotated(v);
          out.add(v);
        }
      case _Kind.palm:
        for (var i = 0; i < 9; i++) {
          final a = i / 9 * math.pi * 2;
          out.add(vm.Vector3(math.cos(a) * 0.8, 0.55, math.sin(a) * 0.8).normalized());
        }
      default:
        final n = kind == _Kind.willow ? 70 : 96;
        for (var i = 0; i < n; i++) {
          // Fibonacci sphere, jittered.
          final y = 1 - (i + 0.5) / n * 2;
          final r = math.sqrt(1 - y * y);
          final a = i * 2.39996 + rnd.nextDouble() * 0.2;
          out.add(vm.Vector3(math.cos(a) * r, y, math.sin(a) * r) * (0.82 + rnd.nextDouble() * 0.18));
        }
    }
    return out;
  }
}

List<_Shell> _program() {
  final rnd = math.Random(42);
  const palettes = [
    [Color(0xFFFF8FD8), Color(0xFFFFFFFF)],
    [Color(0xFF7FE9FF), Color(0xFFB8F6FF)],
    [Color(0xFFFFD27A), Color(0xFFFFF1C9)],
    [Color(0xFFC79BFF), Color(0xFFFF9BD2)],
    [Color(0xFF8BFFB8), Color(0xFFFFFFFF)],
    [Color(0xFFFF7A6B), Color(0xFFFFD27A)],
  ];
  final shells = <_Shell>[];
  var t = 0.6;
  var seed = 1;
  while (t < _showLength - 4) {
    final gap = t < 12
        ? 1.7
        : t < 22
        ? 1.3
        : t < 38
        ? 1.05 - (t - 22) / 16 * 0.45
        : t < 52
        ? 0.28
        : 1.6;
    final count = t >= 38 && t < 52 ? 1 + rnd.nextInt(2) : 1;
    for (var k = 0; k < count; k++) {
      final kinds = t >= 52
          ? [_Kind.willow, _Kind.willow, _Kind.glitter]
          : t >= 38
          ? _Kind.values
          : [_Kind.peony, _Kind.peony, _Kind.ring, _Kind.palm, _Kind.willow, _Kind.glitter];
      final kind = kinds[rnd.nextInt(kinds.length)];
      final pal = kind == _Kind.willow
          ? const [Color(0xFFFFC56B), Color(0xFFFFE3A8)]
          : kind == _Kind.glitter
          ? const [Color(0xFFFFFFFF), Color(0xFFDDE8FF)]
          : palettes[rnd.nextInt(palettes.length)];
      shells.add(
        _Shell(
          t + k * 0.12,
          (rnd.nextDouble() * 2 - 1) * 48,
          120 + rnd.nextDouble() * 40,
          30 + rnd.nextDouble() * 26,
          kind,
          pal,
          seed++,
          scale: t >= 38 && t < 52 ? 1.25 : 1,
        ),
      );
    }
    t += gap * (0.75 + rnd.nextDouble() * 0.5);
  }
  return shells;
}

class FireworksShow extends StatefulWidget {
  const FireworksShow({super.key, required this.brain});
  final LumiBrain brain;

  @override
  State<FireworksShow> createState() => _FireworksShowState();
}

class _FireworksShowState extends State<FireworksShow> {
  final scene = Scene();
  final shells = _program();
  final frame = ValueNotifier(0);
  LumiRig? rig;
  double t = 0;
  bool playing = true;
  bool dragging = false;
  PerspectiveCamera camera = PerspectiveCamera(fovRadiansY: 50 * vm.degrees2Radians);
  Size size = Size.zero;
  double flash = 0;
  Offset? lastBurstScreen;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    await Scene.initializeStaticResources();
    scene.toneMapping = ToneMappingMode.linear;
    final r = await widget.brain.makeRig();
    r.root.position = vm.Vector3(0.35, 1.45, 1.6);
    r.root.scale = vm.Vector3.all(0.82);
    r.showUmbrella = false;
    scene.add(r.root);
    _buildWorld();
    if (mounted) setState(() => rig = r);
  }

  void _buildWorld() {
    // Water: a dark, slightly see-through plane, so the painted reflections
    // behind the scene show through it.
    final water = Node(
      mesh: Mesh(
        PlaneGeometry(width: 600, depth: 600),
        unlit(0.006, 0.006, 0.03, 0.72)..alphaMode = AlphaMode.blend,
      ),
    );
    water.position = vm.Vector3(0, -0.35, 150);
    scene.add(water);

    // The pier, its posts and lantern bulbs.
    final wood = unlit(0.05, 0.03, 0.035);
    final plank = unlit(0.07, 0.045, 0.05);
    final deck = Node(mesh: Mesh(CuboidGeometry(vm.Vector3(2.6, 0.12, 36)), plank));
    deck.position = vm.Vector3(0, 0.0, 14);
    scene.add(deck);
    final bulbs = InstancedMesh(
      geometry: SphereGeometry(radius: 1, segments: 8, rings: 5),
      material: unlit(1, 1, 1),
      sortTransparentInstances: false,
    );
    final postGeo = CuboidGeometry(vm.Vector3(0.12, 1.0, 0.12));
    for (var z = -3.0; z <= 32; z += 2.5) {
      for (final x in [-1.3, 1.3]) {
        final post = Node(mesh: Mesh(postGeo, wood))..position = vm.Vector3(x, 0.45, z);
        scene.add(post);
        bulbs.addInstance(
          vm.Matrix4.translation(vm.Vector3(x, 1.02, z))..scaleByVector3(vm.Vector3.all(0.07)),
          color: vm.Vector4(2.2, 1.2, 0.45, 1),
        );
      }
      // sagging string between posts
      for (var k = 1; k < 5; k++) {
        final f = k / 5;
        for (final x in [-1.3, 1.3]) {
          bulbs.addInstance(
            vm.Matrix4.translation(vm.Vector3(x, 0.98 - math.sin(f * math.pi) * 0.18, z + f * 2.5))
              ..scaleByVector3(vm.Vector3.all(0.03)),
            color: vm.Vector4(1.8, 1.0, 0.4, 1),
          );
        }
      }
    }

    // Castle spires on the far shore.
    final stone = unlit(0.022, 0.018, 0.06);
    final roof = unlit(0.03, 0.02, 0.08);
    final rnd = math.Random(9);
    final towers = [
      [-58.0, 176.0, 2.6, 14.0],
      [-34.0, 168.0, 2.0, 11.0],
      [-12.0, 182.0, 3.0, 22.0],
      [-3.0, 186.0, 2.0, 15.0],
      [9.0, 180.0, 2.6, 19.0],
      [26.0, 170.0, 2.2, 12.0],
      [48.0, 178.0, 2.8, 16.0],
    ];
    for (final tw in towers) {
      final x = tw[0], z = tw[1], r = tw[2], h = tw[3];
      scene.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(bottomRadius: r, topRadius: r * 0.9, height: h, radialSegments: 12),
            stone,
          ),
        )..position = vm.Vector3(x, h / 2 - 0.4, z),
      );
      scene.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(bottomRadius: r * 1.25, topRadius: 0.05, height: h * 0.5, radialSegments: 12),
            roof,
          ),
        )..position = vm.Vector3(x, h + h * 0.25 - 0.4, z),
      );
      // lit windows
      for (var i = 0; i < 4; i++) {
        bulbs.addInstance(
          vm.Matrix4.translation(
            vm.Vector3(x + (rnd.nextDouble() - 0.5) * r, 3 + rnd.nextDouble() * (h - 6), z - r * 0.95),
          )..scaleByVector3(vm.Vector3(0.35, 0.6, 0.1)),
          color: vm.Vector4(2.0, 1.3, 0.5, 1),
        );
      }
      // string lights draped from each roof tip
      for (var k = 0; k < 12; k++) {
        final f = k / 12;
        bulbs.addInstance(
          vm.Matrix4.translation(
            vm.Vector3(x + (f - 0.5) * 9, h * 0.6 - math.sin(f * math.pi) * 3, z - r - 1),
          )..scaleByVector3(vm.Vector3.all(0.3)),
          color: vm.Vector4(2.0, 1.4, 0.6, 1),
        );
      }
    }
    // the low wall of the far shore
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(220, 3, 4)), stone))..position = vm.Vector3(0, 1.1, 164),
    );
    for (var x = -100.0; x <= 100; x += 2.2) {
      bulbs.addInstance(
        vm.Matrix4.translation(vm.Vector3(x, 2.8, 161.8))..scaleByVector3(vm.Vector3.all(0.3)),
        color: vm.Vector4(2.2, 1.5, 0.7, 1),
      );
    }
    final bulbNode = Node()..addComponent(InstancedMeshComponent(bulbs));
    scene.add(bulbNode);
  }

  int get chapterIndex {
    var i = 0;
    for (var k = 0; k < _chapters.length; k++) {
      if (t >= _chapters[k].start) i = k;
    }
    return i;
  }

  void _updateCamera() {
    final i = chapterIndex;
    final c = _chapters[i];
    final prev = _chapters[math.max(0, i - 1)];
    final blend = i == 0 ? 1.0 : Curves.easeInOutCubic.transform(((t - c.start) / 2.2).clamp(0, 1));
    final end = i + 1 < _chapters.length ? _chapters[i + 1].start : _showLength;
    final local = ((t - c.start) / (end - c.start)).clamp(0.0, 1.0);
    vm.Vector3 v(List<double> a) => vm.Vector3(a[0], a[1], a[2]);
    // a slow drift inside each chapter keeps the camera alive
    final drift = vm.Vector3(math.sin(local * 2.4) * 0.6, local * 0.6, -local * 1.2);
    final eye = v(prev.eye) + (v(c.eye) - v(prev.eye)) * blend + drift;
    final target = v(prev.target) + (v(c.target) - v(prev.target)) * blend;
    camera = PerspectiveCamera(
      fovRadiansY: 50 * vm.degrees2Radians,
      position: eye,
      target: target,
      fovFar: 600,
    );
  }

  void _tick(double dt) {
    if (playing && !dragging) {
      t += dt;
      if (t >= _showLength) {
        t = _showLength;
        playing = false;
        setState(() {});
      }
    }
    _updateCamera();
    // Lumi watches the newest burst and glows in its light.
    final r = rig;
    if (r != null) {
      _Shell? latest;
      for (final s in shells) {
        if (s.burst <= t && t - s.burst < s.life) latest = s;
      }
      flash = 0;
      for (final s in shells) {
        final a = t - s.burst;
        if (a >= 0 && a < 0.5) flash = math.max(flash, (1 - a / 0.5) * s.scale);
      }
      final finale = t >= 38 && t < 52;
      r
        ..face = flash > 0.6 ? Face.surprised : (finale ? Face.happy : Face.idle)
        ..handsUp = finale ? 1 : 0
        ..glow = 1 + flash * 0.45
        ..gaze = latest == null ? vm.Vector2(0, -0.6) : vm.Vector2((latest.x / 50).clamp(-1, 1), -0.9);
      r.root.position = vm.Vector3(0.35, 1.45 + math.sin(t * 1.7) * 0.06, 1.6);
      r.update(dt);
    }
    frame.value++;
  }

  void _seek(double nt) {
    setState(() => t = nt.clamp(0, _showLength));
  }

  @override
  void dispose() {
    frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF1A0F3A),
      body: LayoutBuilder(
        builder: (context, c) {
          size = Size(c.maxWidth, c.maxHeight);
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SkyPainter(repaint: frame, state: this, shells: shells),
                ),
              ),
              if (rig != null)
                Positioned.fill(
                  child: SceneView(scene, cameraBuilder: (_) => camera, onTick: (_, dt) => _tick(dt)),
                ),
              // vignette
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 1.1,
                        colors: [Colors.transparent, Color(0x88080418)],
                        stops: [0.6, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: pad.top + 6,
                left: 8,
                right: 16,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    const Spacer(),
                    Text(
                      'Fireworks over the lagoon · High',
                      style: Pd.t(11, w: FontWeight.w600, c: Colors.white70),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: pad.bottom + 14,
                child: ValueListenableBuilder(
                  valueListenable: frame,
                  builder: (_, _, _) => _Timeline(
                    t: t,
                    playing: playing,
                    chapter: chapterIndex,
                    onToggle: () => setState(() {
                      if (t >= _showLength) t = 0;
                      playing = !playing;
                    }),
                    onSeek: _seek,
                    onDrag: (d) => dragging = d,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.t,
    required this.playing,
    required this.chapter,
    required this.onToggle,
    required this.onSeek,
    required this.onDrag,
  });
  final double t;
  final bool playing;
  final int chapter;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;
  final ValueChanged<bool> onDrag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xCC161A3A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onToggle,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (d) {
                        onDrag(true);
                        onSeek(d.localPosition.dx / w * _showLength);
                      },
                      onHorizontalDragUpdate: (d) => onSeek(d.localPosition.dx / w * _showLength),
                      onHorizontalDragEnd: (_) => onDrag(false),
                      onTapDown: (d) => onSeek(d.localPosition.dx / w * _showLength),
                      child: SizedBox(
                        height: 34,
                        child: CustomPaint(painter: _TrackPainter(t / _showLength)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 30,
                child: Text(
                  '${t.round()}s',
                  textAlign: TextAlign.right,
                  style: Pd.t(11.5, w: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _chapters.length; i++)
                GestureDetector(
                  onTap: () => onSeek(_chapters[i].start),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: i == chapter ? const Color(0x33FFFFFF) : const Color(0x14FFFFFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_chapters[i].name, style: Pd.t(10.5, w: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.f);
  final double f;
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(0, y - 2, size.width, y + 2, const Radius.circular(2)),
      Paint()..color = const Color(0x33FFFFFF),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(0, y - 2, size.width * f, y + 2, const Radius.circular(2)),
      Paint()..color = const Color(0xFF8FC8FF),
    );
    for (final c in _chapters.skip(1)) {
      final x = c.start / _showLength * size.width;
      canvas.drawLine(Offset(x, y - 7), Offset(x, y + 7), Paint()..color = const Color(0x55FFFFFF));
    }
    final kx = size.width * f;
    canvas.drawCircle(Offset(kx, y), 12, Paint()..color = const Color(0x33FFFFFF));
    canvas.drawCircle(Offset(kx, y), 8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) => old.f != f;
}

/// Sky, fireworks, and their reflections on the lagoon, painted behind the
/// 3D scene and projected through the same camera.
class _SkyPainter extends CustomPainter {
  _SkyPainter({required Listenable repaint, required this.state, required this.shells})
    : super(repaint: repaint);
  final _FireworksShowState state;
  final List<_Shell> shells;

  static const _waterY = -0.35;
  static const _g = -5.5;

  @override
  void paint(Canvas canvas, Size size) {
    final proj = Projector(state.camera, size);
    final t = state.t;
    final fov = state.camera.fovRadiansY;
    final horizon = proj(0, _waterY, 2000)?.dy ?? size.height * 0.6;

    // sky
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, horizon),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF1B0F45), Color(0xFF3A1F6E), Color(0xFF6A3A92)],
          stops: const [0, 0.65, 1],
        ).createShader(Rect.fromLTRB(0, 0, size.width, math.max(1, horizon))),
    );
    // water
    canvas.drawRect(
      Rect.fromLTRB(0, horizon, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A2266), Color(0xFF120A2A)],
        ).createShader(Rect.fromLTRB(0, horizon, size.width, size.height)),
    );
    // stars
    final rnd = math.Random(17);
    for (var i = 0; i < 120; i++) {
      final dir = vm.Vector3(rnd.nextDouble() * 2 - 1, rnd.nextDouble() * 0.9 + 0.05, 1);
      final p = proj(dir.x * 500, dir.y * 500, 500);
      if (p == null || p.dy > horizon) continue;
      canvas.drawCircle(p, 0.6 + rnd.nextDouble(), Paint()..color = Colors.white.withValues(alpha: 0.5));
    }

    // smoke haze builds up during the show
    final haze = (t / _showLength).clamp(0.0, 1.0);
    final hazeRect = Rect.fromLTRB(0, horizon - size.height * 0.35, size.width, horizon);
    canvas.drawRect(
      hazeRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color.fromRGBO(200, 150, 255, 0.10 + 0.16 * haze), const Color(0x00C896FF)],
        ).createShader(hazeRect),
    );

    final add = Paint()..blendMode = BlendMode.plus;
    final glowPaint = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, horizon));
    _drawShells(canvas, proj, t, fov, add, glowPaint, reflect: false, horizon: horizon);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, horizon, size.width, size.height));
    _drawShells(canvas, proj, t, fov, add, glowPaint, reflect: true, horizon: horizon);
    canvas.restore();
  }

  void _drawShells(
    Canvas canvas,
    Projector proj,
    double t,
    double fov,
    Paint add,
    Paint glow, {
    required bool reflect,
    required double horizon,
  }) {
    final alphaMul = reflect ? 0.35 : 1.0;
    double ry(double y) => reflect ? 2 * _waterY - y : y;
    for (final s in shells) {
      if (t < s.launch || t > s.burst + s.life) continue;
      if (t < s.burst) {
        // rising comet with a short trail
        final f = Curves.easeOutQuad.transform((t - s.launch) / _Shell.rise);
        final y = f * s.height;
        final p = proj(s.x, ry(y), s.z);
        final p0 = proj(s.x, ry(math.max(0, y - 3)), s.z);
        if (p == null || p0 == null) continue;
        add
          ..color = const Color(0xFFFFE0B0).withValues(alpha: 0.9 * alphaMul)
          ..strokeWidth = 1.4;
        canvas.drawLine(p0, p, add);
        continue;
      }
      final age = t - s.burst;
      final lifeF = age / s.life;
      final fade = (1 - lifeF).clamp(0.0, 1.0);
      final willow = s.kind == _Kind.willow;
      final k = willow ? 1.6 : 1.15;
      final speed = (willow ? 17.0 : 23.0) * s.scale;
      final grav = willow ? _g * 1.4 : _g;
      final spread = (1 - math.exp(-k * age)) / k;
      final spread0 = (1 - math.exp(-k * math.max(0, age - (willow ? 0.6 : 0.18)))) / k;
      final bx = s.x, by = s.height, bz = s.z;

      // flash at the burst
      if (age < 0.35) {
        final c = proj(bx, ry(by), bz);
        if (c != null) {
          final sc = proj.scaleAt(bx, by, bz, fov);
          glow.color = s.colors.first.withValues(alpha: (1 - age / 0.35) * 0.35 * alphaMul);
          canvas.drawCircle(c, 3.5 * sc * s.scale, glow);
        }
      }

      for (var i = 0; i < s.dirs.length; i++) {
        final d = s.dirs[i];
        final col = s.colors[i % s.colors.length];
        final x = bx + d.x * speed * spread;
        final y = by + d.y * speed * spread + 0.5 * grav * age * age;
        final z = bz + d.z * speed * spread;
        final p = proj(x, ry(y), z);
        if (p == null) continue;
        final a0 = math.max(0.0, age - (willow ? 0.6 : 0.18));
        final x0 = bx + d.x * speed * spread0;
        final y0 = by + d.y * speed * spread0 + 0.5 * grav * a0 * a0;
        final z0 = bz + d.z * speed * spread0;
        final q = proj(x0, ry(y0), z0);
        var a = fade;
        if (s.kind == _Kind.glitter) {
          a *= (math.sin(age * 40 + i * 1.7) > 0.2) ? 1 : 0.15;
        }
        a *= alphaMul;
        if (q != null) {
          add
            ..color = col.withValues(alpha: a * (willow ? 0.55 : 0.7))
            ..strokeWidth = willow ? 1.2 : 1.6
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(q, p, add);
        }
        add.color = col.withValues(alpha: a);
        canvas.drawCircle(p, (willow ? 1.5 : 2.1) * (1.2 - lifeF * 0.5), add);
        if (s.kind == _Kind.palm) {
          // palms trail sparks behind each arm
          for (var j = 1; j < 6; j++) {
            final aj = math.max(0.0, age - j * 0.08);
            final sj = (1 - math.exp(-k * aj)) / k;
            final pj = proj(
              bx + d.x * speed * sj,
              ry(by + d.y * speed * sj + 0.5 * grav * aj * aj),
              bz + d.z * speed * sj,
            );
            if (pj != null) {
              add.color = col.withValues(alpha: a * (1 - j / 6));
              canvas.drawCircle(pj, 1.6, add);
            }
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) => false;
}
