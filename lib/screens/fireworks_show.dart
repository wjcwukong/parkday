import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../lumi/lumi_brain.dart';
import '../scene/fx.dart';
import '../scene/lumi_rig.dart';
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
  // Close shots turn around and look back at Lumi's face, with the pier
  // and its lanterns behind it.
  _Chapter('close-up', 12, [0.5, 2.05, 5.0], [0.35, 1.35, 1.6]),
  _Chapter('build', 22, [-0.6, 3.2, -9.0], [0.0, 12.0, 60.0]),
  _Chapter('finale', 38, [-2.4, 4.6, -11.0], [0.0, 15.0, 70.0]),
  _Chapter('afterglow', 52, [-1.5, 2.5, 4.6], [0.35, 2.1, 1.6]),
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

  static vm.Vector3 _light(Color c, double gain) {
    double lin(double v) => math.pow(v, 2.2).toDouble() * gain;
    return vm.Vector3(lin(c.r), lin(c.g), lin(c.b));
  }

  /// Adds this shell to the show mesh: the rising comet, the burst flash,
  /// the stars with their trails, and the smoke they leave behind. Mirrors
  /// the motion the old painter computed, now evaluated in `sparks.fmat`.
  void emit(SparkBuilder b) {
    final rnd = math.Random(seed * 31 + 7);
    final at = vm.Vector3(x, height, z);
    final willow = kind == _Kind.willow;
    final palm = kind == _Kind.palm;
    const g = -5.5;

    // Comet: drag k, reaching the burst height after `rise` seconds.
    const k = 0.8;
    final climb = (height - 0.5 * g * rise * rise) * k / (1 - math.exp(-k * rise));
    b.add(
      origin: vm.Vector3(x, 0, z),
      velocity: vm.Vector3(0, climb, 0),
      start: launch,
      life: rise,
      color: vm.Vector3(1.6, 1.1, 0.6),
      size: 0.1,
      drag: k,
      gravity: g,
      trail: 0.35,
      kind: SparkKind.comet,
    );

    b.add(
      origin: at,
      start: burst,
      life: 0.7,
      color: _light(colors.first, 1.4),
      size: 9 * scale,
      kind: SparkKind.flash,
    );

    final speed = (willow ? 17.0 : (palm ? 20.0 : 23.0)) * scale;
    for (var i = 0; i < dirs.length; i++) {
      final c = _light(colors[i % colors.length], willow ? 3.0 : 4.5);
      b.add(
        origin: at,
        velocity: dirs[i] * speed,
        start: burst,
        life: life * (0.85 + rnd.nextDouble() * 0.15),
        color: c,
        size: palm ? 0.34 : (willow ? 0.18 : 0.24),
        drag: willow ? 1.6 : 1.15,
        gravity: willow ? g * 1.4 : g,
        trail: palm ? 0.5 : (willow ? 0.7 : 0.2),
        kind: kind == _Kind.glitter || (willow && i.isEven) ? SparkKind.glitter : SparkKind.spark,
      );
    }

    // Smoke the burst leaves hanging, lit in its colors.
    for (var i = 0; i < 6; i++) {
      final off = vm.Vector3(rnd.nextDouble() - 0.5, rnd.nextDouble() - 0.6, rnd.nextDouble() - 0.5) * 14 * scale;
      b.add(
        origin: at + off,
        velocity: vm.Vector3(0.9 + rnd.nextDouble() * 0.6, -0.2, 0),
        start: burst + 0.15,
        life: 9 + rnd.nextDouble() * 4,
        color: _light(colors.first, 0.05),
        size: (9 + rnd.nextDouble() * 6) * scale,
        kind: SparkKind.smoke,
      );
    }
  }

  List<vm.Vector3> _dirs() {
    final rnd = math.Random(seed);
    final out = <vm.Vector3>[];
    switch (kind) {
      case _Kind.ring:
        final tilt = rnd.nextDouble() * 0.9 - 0.45;
        // Keep rings turned mostly towards the audience.
        final yaw = (rnd.nextDouble() - 0.5) * 1.2;
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
        final n = kind == _Kind.willow ? 90 : 140;
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
  double _clock = 0;
  PreprocessedMaterial? lagoon;
  PreprocessedMaterial? sparks;

  static const _waterY = -0.35;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    await Scene.initializeStaticResources();
    // A night look: a gradient sky with a moon, purple haze that swallows
    // the far shore, and bloom so every spark and lantern glows.
    scene.environmentSettings = EnvironmentSettings(
      skybox: Skybox(
        GradientSkySource(
          zenithColor: vm.Vector3(0.03, 0.014, 0.11),
          horizonColor: vm.Vector3(0.2, 0.08, 0.34),
          groundColor: vm.Vector3(0.02, 0.01, 0.05),
          // The moon is a glow in the spark mesh; the sky's own sun disk
          // and its wide halo are switched off.
          sunDirection: _moonDir,
          sunColor: vm.Vector3.zero(),
        ),
      ),
      toneMapping: ToneMappingMode.pbrNeutral,
      exposure: 1.0,
      bloomEnabled: true,
      bloomThreshold: 0.9,
      bloomIntensity: 0.35,
      bloomScatter: 0.65,
      fogEnabled: true,
      fogMode: FogMode.exponential,
      fogColor: vm.Vector3(0.075, 0.032, 0.15),
      fogDensity: 0.006,
      fogMaxOpacity: 0.85,
      vignetteEnabled: true,
      vignetteIntensity: 0.4,
    );
    scene.depthOfField
      ..fStop = 1.2
      ..blurScale = 2.0
      ..quality = DepthOfFieldQuality.medium;
    final r = await widget.brain.makeRig();
    r.root.position = vm.Vector3(0.35, 1.45, 1.6);
    r.root.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.pi);
    r.root.scale = vm.Vector3.all(0.82);
    r.showUmbrella = false;
    scene.add(r.root);
    await _buildWorld();
    if (mounted) setState(() => rig = r);
  }

  static final _moonDir = vm.Vector3(-0.05, 0.36, 0.93).normalized();

  Future<void> _buildWorld() async {
    // Water: a mirror of the whole scene, rippled in its material.
    lagoon = await loadFmatMaterial('assets/materials/lagoon.fmat');
    final water = Node(mesh: Mesh(PlaneGeometry(width: 600, depth: 600), lagoon!))
      ..addComponent(PlanarReflectorComponent(resolutionScale: 0.5));
    water.position = vm.Vector3(0, _waterY, 150);
    scene.add(water);

    // The whole show is one mesh of sparks moved on the GPU by `time`.
    sparks = await loadFmatMaterial('assets/materials/sparks.fmat');
    final b = SparkBuilder();
    for (final s in shells) {
      s.emit(b);
    }
    _stars(b);
    scene.add(
      Node(name: 'show', mesh: b.build(sparks!, vm.Aabb3.minMax(vm.Vector3.all(-700), vm.Vector3.all(700)))),
    );

    // The pier, its posts and lantern bulbs.
    final wood = unlit(0.05, 0.03, 0.035);
    final plank = unlit(0.07, 0.045, 0.05);
    // It runs far back behind Lumi too, so the close shots looking back
    // see a long boardwalk of lanterns fading into the haze.
    final deck = Node(mesh: Mesh(CuboidGeometry(vm.Vector3(2.6, 0.12, 77)), plank));
    deck.position = vm.Vector3(0, 0.0, -6.5);
    scene.add(deck);
    final seams = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(2.6, 0.02, 0.03)),
      material: unlit(0.03, 0.018, 0.025),
      sortTransparentInstances: false,
    );
    for (var z = -45.0; z <= 32; z += 0.45) {
      seams.addInstance(vm.Matrix4.translation(vm.Vector3(0, 0.065, z)));
    }
    scene.add(Node()..addComponent(InstancedMeshComponent(seams)));
    final bulbs = InstancedMesh(
      geometry: SphereGeometry(radius: 1, segments: 8, rings: 5),
      material: unlit(1, 1, 1),
      sortTransparentInstances: false,
    );
    final postGeo = CuboidGeometry(vm.Vector3(0.12, 1.0, 0.12));
    for (var z = -45.0; z <= 32; z += 2.5) {
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

  /// Stars on a far dome, plus the moon's halo around the sky's moon disk.
  void _stars(SparkBuilder b) {
    final rnd = math.Random(17);
    for (var i = 0; i < 260; i++) {
      final d = vm.Vector3(rnd.nextDouble() * 2 - 1, 0.04 + rnd.nextDouble() * 0.9, 0.2 + rnd.nextDouble() * 0.8)
        ..normalize();
      b.add(
        origin: d * 480,
        start: -1000,
        life: 1e5,
        color: vm.Vector3(1.0, 0.95, 1.2) * (0.25 + rnd.nextDouble() * 0.6),
        size: 0.8 + rnd.nextDouble() * 1.2,
        kind: SparkKind.star,
      );
    }
    b.add(
      origin: _moonDir * 470,
      start: -1000,
      life: 1e5,
      color: vm.Vector3(0.4, 0.36, 0.62),
      size: 80,
      kind: SparkKind.glow,
    );
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
    // Swinging between a shot behind Lumi and one in front of it arcs
    // around Lumi instead of flying through it.
    final turns = (prev.eye[2] < 1.6) != (c.eye[2] < 1.6);
    final arc = turns ? vm.Vector3(math.sin(blend * math.pi) * 3.2, math.sin(blend * math.pi) * 0.8, 0) : vm.Vector3.zero();
    final eye = v(prev.eye) + (v(c.eye) - v(prev.eye)) * blend + drift * (c.eye[2] < 1.6 ? 1.0 : 0.25) + arc;
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
    _clock += dt;
    sparks?.parameters.setFloat('time', t);
    lagoon?.parameters.setFloat('time', _clock);
    // Depth of field only for the shots framed on Lumi.
    final ci = chapterIndex;
    final dof = ci == 1 || ci == 4;
    scene.depthOfField.enabled = dof;
    if (dof) scene.depthOfField.focusDistance = camera.position.distanceTo(vm.Vector3(0.35, 2.0, 1.6));
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
        ..gaze = latest == null ? vm.Vector2(0, -0.6) : vm.Vector2((-latest.x / 50).clamp(-1, 1), -0.9);
      r.root.position = vm.Vector3(0.35, 1.45 + math.sin(t * 1.7) * 0.06, 1.6);
      // Lumi faces the show (+Z); its face shows only when the camera is in front.
      r.faceShown = camera.position.z > 1.6;
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
              if (rig != null)
                Positioned.fill(
                  child: SceneView(scene, cameraBuilder: (_) => camera, onTick: (_, dt) => _tick(dt)),
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
