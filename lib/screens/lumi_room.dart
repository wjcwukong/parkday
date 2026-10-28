import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene/scene.dart' as fs show Material;
import 'package:vector_math/vector_math.dart' as vm;

import '../lumi/lumi_brain.dart';
import '../scene/lumi_rig.dart';
import '../theme.dart';

PhysicallyBasedMaterial _pbr(double r, double g, double b, {double rough = 0.8, double emissive = 0}) {
  final m = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(r, g, b, 1)
    ..metallicFactor = 0
    ..roughnessFactor = rough;
  if (emissive > 0) {
    m.emissiveFactor = vm.Vector4(r, g, b, 1);
    m.emissiveStrength = emissive;
  }
  return m;
}

Node _mesh(Geometry g, fs.Material m, {vm.Vector3? at, vm.Quaternion? rot, vm.Vector3? scale}) {
  final n = Node(mesh: Mesh(g, m));
  if (at != null) n.position = at;
  if (rot != null) n.rotation = rot;
  if (scale != null) n.scale = scale;
  return n;
}

/// Lumi's floating treehouse room: tap a hat to wear it, tap the cushion
/// for a nap, drag to look around.
class LumiRoom extends StatefulWidget {
  const LumiRoom({super.key, required this.brain});
  final LumiBrain brain;

  @override
  State<LumiRoom> createState() => _LumiRoomState();
}

class _LumiRoomState extends State<LumiRoom> {
  final scene = Scene();
  LumiRig? rig;
  double azimuth = 0.55, elevation = 0.33, _azVel = 0;
  double t = 0;
  Size size = Size.zero;
  late PerspectiveCamera camera = _cam();
  final hatSpots = <Hat, vm.Vector3>{};
  final hatNodes = <Hat, Node>{};
  final cushion = vm.Vector3(0.95, 0.35, -0.55);
  bool napping = false;
  vm.Vector3 lumiTarget = vm.Vector3(-0.15, 1.55, 0.1);
  vm.Vector3 lumiPos = vm.Vector3(-0.15, 1.55, 0.1);
  String? toast;
  double toastT = 0;

  @override
  void initState() {
    super.initState();
    _build();
  }

  PerspectiveCamera _cam() {
    const r = 12.5;
    final target = vm.Vector3(0, 0.55, 0.1);
    final eye =
        target +
        vm.Vector3(
          math.sin(azimuth) * math.cos(elevation) * r,
          math.sin(elevation) * r,
          -math.cos(azimuth) * math.cos(elevation) * r,
        );
    return PerspectiveCamera(fovRadiansY: 46 * vm.degrees2Radians, position: eye, target: target, fovFar: 80);
  }

  Future<void> _build() async {
    await Scene.initializeStaticResources();
    scene.environmentIntensity = 0.22;
    scene.toneMapping = ToneMappingMode.aces;
    scene.exposure = 1.1;

    final wood = _pbr(0.42, 0.24, 0.14, rough: 0.7);
    final woodDark = _pbr(0.18, 0.09, 0.06);
    final wall = _pbr(0.30, 0.17, 0.2, rough: 0.9);
    final rugA = _pbr(0.85, 0.55, 0.62);
    final rugB = _pbr(0.98, 0.82, 0.78);

    // floating island: deck, rim and the root bulb underneath
    scene.add(
      _mesh(
        CylinderGeometry(bottomRadius: 2.25, topRadius: 2.3, height: 0.32, radialSegments: 48),
        wood,
        at: vm.Vector3(0, 0.0, 0),
      ),
    );
    scene.add(
      _mesh(
        CylinderGeometry(bottomRadius: 0.5, topRadius: 2.2, height: 1.3, radialSegments: 48),
        woodDark,
        at: vm.Vector3(0, -0.8, 0),
      ),
    );
    for (var i = 0; i < 18; i++) {
      final a = i / 18 * math.pi * 2;
      scene.add(
        _mesh(
          CuboidGeometry(vm.Vector3(0.05, 0.02, 0.8)),
          woodDark,
          at: vm.Vector3(math.cos(a) * 1.4, 0.17, math.sin(a) * 1.4),
          rot: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -a),
        ),
      );
    }
    // ladder dangling below
    for (final x in [-0.22, 0.22]) {
      scene.add(
        _mesh(
          CylinderGeometry(bottomRadius: 0.025, topRadius: 0.025, height: 2.2),
          woodDark,
          at: vm.Vector3(-1.1 + x, -1.3, -1.6),
        ),
      );
    }
    for (var k = 0; k < 7; k++) {
      scene.add(
        _mesh(
          CuboidGeometry(vm.Vector3(0.48, 0.04, 0.05)),
          woodDark,
          at: vm.Vector3(-1.1, -0.35 - k * 0.3, -1.6),
        ),
      );
    }

    // two walls forming the back corner
    scene.add(_mesh(CuboidGeometry(vm.Vector3(3.9, 2.7, 0.14)), wall, at: vm.Vector3(0.05, 1.5, 1.55)));
    scene.add(_mesh(CuboidGeometry(vm.Vector3(0.14, 2.7, 2.6)), wall, at: vm.Vector3(-1.62, 1.5, 0.25)));
    // round window with the moon
    scene.add(
      _mesh(
        TorusGeometry(radius: 0.55, tubeRadius: 0.07, radialSegments: 40),
        _pbr(0.55, 0.36, 0.22),
        at: vm.Vector3(0.55, 1.75, 1.47),
        rot: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
      ),
    );
    scene.add(
      _mesh(
        DiscGeometry(radius: 0.55, segments: 40),
        unlit(0.06, 0.08, 0.32)..depthLayer = 1,
        at: vm.Vector3(0.55, 1.75, 1.47),
        rot: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -math.pi / 2),
      ),
    );
    scene.add(_mesh(SphereGeometry(radius: 0.2), unlit(2.2, 2.3, 2.6), at: vm.Vector3(0.68, 1.85, 1.42)));

    // fairy lights along the top of both walls
    final bulbs = InstancedMesh(
      geometry: SphereGeometry(radius: 1, segments: 8, rings: 5),
      material: unlit(1, 1, 1),
      sortTransparentInstances: false,
    );
    void strand(vm.Vector3 a, vm.Vector3 b, int n, double sag) {
      for (var i = 0; i <= n; i++) {
        final f = i / n;
        final p = a + (b - a) * f - vm.Vector3(0, math.sin(f * math.pi) * sag, 0);
        bulbs.addInstance(
          vm.Matrix4.translation(p)..scaleByVector3(vm.Vector3.all(0.045)),
          color: vm.Vector4(2.4, 1.6, 0.6, 1),
        );
      }
    }

    strand(vm.Vector3(-1.5, 2.65, 1.42), vm.Vector3(0.0, 2.6, 1.42), 9, 0.22);
    strand(vm.Vector3(0.0, 2.6, 1.42), vm.Vector3(1.9, 2.7, 1.42), 10, 0.25);
    strand(vm.Vector3(-1.52, 2.65, 1.4), vm.Vector3(-1.52, 2.55, -0.9), 11, 0.28);
    scene.add(Node()..addComponent(InstancedMeshComponent(bulbs)));

    // floor rug
    scene.add(
      _mesh(DiscGeometry(radius: 1.0, segments: 48), rugA..depthLayer = 1, at: vm.Vector3(-0.1, 0.161, 0.1)),
    );
    scene.add(
      _mesh(
        RingGeometry(innerRadius: 0.5, outerRadius: 0.72, segments: 48),
        rugB..depthLayer = 2,
        at: vm.Vector3(-0.1, 0.161, 0.1),
      ),
    );

    // nap cushion
    scene.add(
      _mesh(
        TorusGeometry(radius: 0.36, tubeRadius: 0.13, radialSegments: 36),
        _pbr(0.55, 0.42, 0.85),
        at: cushion + vm.Vector3(0, -0.08, 0),
      ),
    );
    scene.add(
      _mesh(
        CylinderGeometry(bottomRadius: 0.36, topRadius: 0.36, height: 0.12, radialSegments: 36),
        _pbr(0.7, 0.6, 0.95),
        at: cushion + vm.Vector3(0, -0.1, 0),
      ),
    );

    // floor lamp
    scene.add(
      _mesh(
        CylinderGeometry(bottomRadius: 0.025, topRadius: 0.025, height: 1.5),
        woodDark,
        at: vm.Vector3(1.5, 0.9, 0.9),
      ),
    );
    scene.add(
      _mesh(
        CylinderGeometry(bottomRadius: 0.26, topRadius: 0.16, height: 0.36, radialSegments: 24),
        _pbr(1.0, 0.85, 0.6, emissive: 1.6),
        at: vm.Vector3(1.5, 1.72, 0.9),
      ),
    );
    final lamp = Node()..position = vm.Vector3(1.4, 1.6, 0.6);
    lamp.addComponent(
      PointLightComponent(PointLight(color: vm.Vector3(1.0, 0.7, 0.4), intensity: 7, range: 7)),
    );
    scene.add(lamp);
    final moonLight = Node()..position = vm.Vector3(0.4, 2.0, 0.6);
    moonLight.addComponent(
      PointLightComponent(PointLight(color: vm.Vector3(0.5, 0.6, 1.0), intensity: 3, range: 5)),
    );
    scene.add(moonLight);
    final fill = Node()..position = vm.Vector3(-1.0, 2.6, -2.5);
    fill.addComponent(
      PointLightComponent(PointLight(color: vm.Vector3(0.75, 0.6, 1.0), intensity: 6, range: 9)),
    );
    scene.add(fill);

    // potted plant
    scene.add(
      _mesh(
        CylinderGeometry(bottomRadius: 0.17, topRadius: 0.22, height: 0.36, radialSegments: 20),
        _pbr(0.75, 0.38, 0.25),
        at: vm.Vector3(1.55, 0.35, -0.35),
      ),
    );
    final leaf = _pbr(0.18, 0.55, 0.3, rough: 0.6);
    for (var i = 0; i < 7; i++) {
      final a = i / 7 * math.pi * 2;
      scene.add(
        _mesh(
          SphereGeometry(radius: 1, segments: 16, rings: 8),
          leaf,
          at: vm.Vector3(1.55 + math.cos(a) * 0.13, 0.75 + (i % 3) * 0.1, -0.35 + math.sin(a) * 0.13),
          scale: vm.Vector3.all(0.14),
        ),
      );
    }

    // hat shelf on the left wall
    scene.add(_mesh(CuboidGeometry(vm.Vector3(0.3, 0.06, 2.1)), wood, at: vm.Vector3(-1.4, 1.28, 0.3)));
    const order = [Hat.starSprout, Hat.beanie, Hat.flowerCrown, Hat.headphones, Hat.catEars];
    for (var i = 0; i < order.length; i++) {
      final h = order[i];
      if (h == Hat.catEars && widget.brain.keys < 5) continue;
      final p = vm.Vector3(-1.38, 1.36, -0.55 + i * 0.42);
      final n = buildHat(h)
        ..position = p + vm.Vector3(0, 0.05, 0)
        ..scale = vm.Vector3.all(0.42);
      scene.add(n);
      hatSpots[h] = p;
      hatNodes[h] = n;
    }

    final r = await widget.brain.makeRig();
    r.showUmbrella = false;
    r.root.scale = vm.Vector3.all(0.62);
    scene.add(r.root);
    _syncShelf(r.hat);
    if (mounted) setState(() => rig = r);
  }

  void _syncShelf(Hat worn) {
    hatNodes.forEach((h, n) => n.visible = h != worn);
  }

  void _say(String s) {
    setState(() {
      toast = s;
      toastT = 2.4;
    });
  }

  void _tap(Offset p) {
    final ray = camera.screenPointToRay(p, size);
    // Lumi first
    final r = rig;
    if (r == null) return;
    final lumiHit = ray.intersectsWithSphere(vm.Sphere.centerRadius(lumiPos, 0.45));
    if (lumiHit != null) {
      if (napping) {
        napping = false;
        lumiTarget = vm.Vector3(-0.15, 1.55, 0.1);
        widget.brain.speak('*yawn* Good nap!', 2);
        _say('*yawn* Good nap!');
      } else {
        r.squashY = 0.8;
        Future.delayed(const Duration(milliseconds: 140), () => r.squashY = 1.1);
        Future.delayed(const Duration(milliseconds: 300), () => r.squashY = 1);
        _say('Hehe!');
      }
      return;
    }
    for (final e in hatSpots.entries) {
      if (ray.intersectsWithSphere(vm.Sphere.centerRadius(e.value + vm.Vector3(0, 0.1, 0), 0.24)) != null) {
        final h = r.hat == e.key ? Hat.none : e.key;
        r.hat = h;
        widget.brain.setHat(h);
        _syncShelf(h);
        r.squashY = 1.18;
        Future.delayed(const Duration(milliseconds: 160), () => r.squashY = 0.9);
        Future.delayed(const Duration(milliseconds: 320), () => r.squashY = 1);
        _say(h == Hat.none ? 'Back on the shelf' : 'Looking sharp!');
        return;
      }
    }
    if (ray.intersectsWithSphere(vm.Sphere.centerRadius(cushion, 0.55)) != null) {
      napping = true;
      lumiTarget = cushion + vm.Vector3(0, 0.62, 0);
      _say('Nap time… zzz');
    }
  }

  void _tick(double dt) {
    t += dt;
    if (!_dragging) {
      azimuth += _azVel * dt;
      _azVel *= math.exp(-dt * 3);
    }
    camera = _cam();
    final r = rig;
    if (r == null) return;
    final k = 1 - math.exp(-dt * 3);
    lumiPos = lumiPos + (lumiTarget - lumiPos) * k;
    final bob = napping ? math.sin(t * 1.3) * 0.02 : math.sin(t * 1.8) * 0.06;
    r.root.position = lumiPos + vm.Vector3(0, bob, 0);
    // face the camera
    r.root.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -azimuth);
    r
      ..face = napping ? Face.asleep : Face.idle
      ..glow = napping ? 0.7 : 1
      ..tilt = napping ? 0.25 : 0
      ..blush = napping ? 0.3 : 0;
    r.update(dt);
    if (toastT > 0) {
      toastT -= dt;
      if (toastT <= 0) setState(() => toast = null);
    }
  }

  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Pd.bgDeep,
      body: LayoutBuilder(
        builder: (context, c) {
          size = Size(c.maxWidth, c.maxHeight);
          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.1),
                      radius: 1.0,
                      colors: [Color(0xFF2A2A66), Color(0xFF121538), Color(0xFF080A20)],
                      stops: [0, 0.6, 1],
                    ),
                  ),
                ),
              ),
              if (rig != null)
                Positioned.fill(
                  child: GestureDetector(
                    onTapUp: (d) => _tap(d.localPosition),
                    onHorizontalDragStart: (_) => _dragging = true,
                    onHorizontalDragUpdate: (d) {
                      azimuth -= d.delta.dx * 0.008;
                      _azVel = -d.delta.dx * 0.5;
                    },
                    onHorizontalDragEnd: (_) => _dragging = false,
                    child: SceneView(scene, cameraBuilder: (_) => camera, onTick: (_, dt) => _tick(dt)),
                  ),
                )
              else
                const Center(child: CircularProgressIndicator(color: Pd.lumiBlue)),
              Positioned(
                top: pad.top + 4,
                left: 4,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    Text('${rig?.style.name ?? 'Lumi'}’s room', style: Pd.t(15, w: FontWeight.w700)),
                  ],
                ),
              ),
              if (toast != null)
                Positioned(
                  top: pad.top + 64,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xE0232955),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(toast!, style: Pd.t(12, w: FontWeight.w600)),
                    ),
                  ),
                ),
              Positioned(
                bottom: pad.bottom + 28,
                left: 0,
                right: 0,
                child: Text(
                  'Tap a hat to wear it · tap the cushion for a nap',
                  textAlign: TextAlign.center,
                  style: Pd.t(11, c: Pd.textDim),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
