import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene/scene.dart' as fs show Material;
import 'package:vector_math/vector_math.dart' as vm;

import '../data/park_data.dart';
import '../lumi/lumi_brain.dart';
import '../scene/lumi_rig.dart';
import '../scene/space.dart';
import '../theme.dart';

PhysicallyBasedMaterial _pbr(double r, double g, double b, {double rough = 0.85}) => PhysicallyBasedMaterial()
  ..baseColorFactor = vm.Vector4(r, g, b, 1)
  ..metallicFactor = 0
  ..roughnessFactor = rough;

final _plaza = vm.Vector3(0.6, 0, -1.9);

Node _m(Geometry g, fs.Material mat, {vm.Vector3? at, vm.Quaternion? rot, vm.Vector3? scale}) {
  final n = Node(mesh: Mesh(g, mat));
  if (at != null) n.position = at;
  if (rot != null) n.rotation = rot;
  if (scale != null) n.scale = scale;
  return n;
}

/// A cone whose segments alternate between two colors (a striped canopy).
Geometry stripedCone(double radius, double height, int stripes, vm.Vector4 a, vm.Vector4 b) {
  final pos = <double>[], nor = <double>[], col = <double>[];
  final idx = <int>[];
  final segs = stripes * 3;
  final slope = radius / height;
  for (var i = 0; i < segs; i++) {
    final a0 = i / segs * math.pi * 2, a1 = (i + 1) / segs * math.pi * 2;
    final c = (i ~/ 3).isEven ? a : b;
    final base = pos.length ~/ 3;
    void v(double x, double y, double z, double nx, double ny, double nz) {
      pos.addAll([x, y, z]);
      final l = math.sqrt(nx * nx + ny * ny + nz * nz);
      nor.addAll([nx / l, ny / l, nz / l]);
      col.addAll([c.x, c.y, c.z, c.w]);
    }

    final am = (a0 + a1) / 2;
    v(0, height, 0, math.cos(am), slope, math.sin(am));
    v(math.cos(a0) * radius, 0, math.sin(a0) * radius, math.cos(a0), slope, math.sin(a0));
    v(math.cos(a1) * radius, 0, math.sin(a1) * radius, math.cos(a1), slope, math.sin(a1));
    // underside so the canopy reads from low angles too
    v(0, height * 0.6, 0, 0, -1, 0);
    v(math.cos(a0) * radius, 0, math.sin(a0) * radius, 0, -1, 0);
    v(math.cos(a1) * radius, 0, math.sin(a1) * radius, 0, -1, 0);
    idx.addAll([base, base + 2, base + 1, base + 3, base + 4, base + 5]);
  }
  return MeshGeometry.fromArrays(
    positions: Float32List.fromList(pos),
    normals: Float32List.fromList(nor),
    colors: Float32List.fromList(col),
    indices: idx,
  );
}

class ParkMapScreen extends StatefulWidget {
  const ParkMapScreen({super.key, required this.brain});
  final LumiBrain brain;

  @override
  State<ParkMapScreen> createState() => _ParkMapScreenState();
}

class _ParkMapScreenState extends State<ParkMapScreen> {
  final scene = Scene();
  final frame = ValueNotifier(0);
  LumiRig? rig;
  Size size = Size.zero;
  double t = 0;
  double azimuth = 0.35, elevation = 0.92, distance = 14.5;
  vm.Vector3 target = vm.Vector3(-0.2, 0, 0.2);
  late PerspectiveCamera camera = _cam();

  // animated rides
  final spinners = <(Node, double)>[];
  Node? dropRing;

  // Lumi hopping
  vm.Vector3 lumiFrom = _plaza.clone();
  vm.Vector3 lumiTo = _plaza.clone();
  double hopT = 1, hopLen = 0;
  Ride? heading;
  bool arrived = false;

  @override
  void initState() {
    super.initState();
    _build();
  }

  PerspectiveCamera _cam() {
    final eye =
        target +
        vm.Vector3(
          math.sin(azimuth) * math.cos(elevation) * distance,
          math.sin(elevation) * distance,
          -math.cos(azimuth) * math.cos(elevation) * distance,
        );
    return PerspectiveCamera(
      fovRadiansY: 48 * vm.degrees2Radians,
      position: eye,
      target: target,
      fovFar: 120,
    );
  }

  Future<void> _build() async {
    await Scene.initializeStaticResources();
    scene.toneMapping = ToneMappingMode.aces;
    scene.environmentIntensity = 0.55;
    scene.exposure = 1.0;
    final sun = Node();
    sun.addComponent(
      DirectionalLightComponent(
        DirectionalLight(
          direction: vm.Vector3(0.4, -1, 0.5),
          intensity: 2.6,
          color: vm.Vector3(1, 0.95, 0.88),
        ),
      ),
    );
    scene.add(sun);

    // water and island
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 14, topRadius: 14, height: 0.2, radialSegments: 64),
        _pbr(0.12, 0.38, 0.62, rough: 0.3),
        at: vm.Vector3(0, -0.45, 0),
      ),
    );
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 6.6, topRadius: 6.3, height: 0.7, radialSegments: 64),
        _pbr(0.85, 0.75, 0.55),
        at: vm.Vector3(0, -0.36, 0),
      ),
    );
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 6.2, topRadius: 6.2, height: 0.1, radialSegments: 64),
        _pbr(0.36, 0.66, 0.32),
        at: vm.Vector3(0, 0.0, 0),
      ),
    );
    final hill = _pbr(0.32, 0.6, 0.3);
    final rnd = math.Random(4);
    for (var i = 0; i < 7; i++) {
      final a = rnd.nextDouble() * math.pi * 2, r = 3.6 + rnd.nextDouble() * 2;
      scene.add(
        _m(
          SphereGeometry(radius: 1, segments: 24, rings: 12),
          hill,
          at: vm.Vector3(math.cos(a) * r, -0.35, math.sin(a) * r),
          scale: vm.Vector3(1, 0.45, 1) * (0.8 + rnd.nextDouble()),
        ),
      );
    }

    // stepping-stone paths from the plaza to each ride
    final stones = InstancedMesh(
      geometry: CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 12),
      material: _pbr(0.78, 0.68, 0.58),
    );
    final plaza = _plaza;
    for (final ride in rides) {
      final end = vm.Vector3(ride.x, 0, ride.z);
      final mid = (plaza + end) * 0.5 + vm.Vector3(rnd.nextDouble() - 0.5, 0, rnd.nextDouble() - 0.5) * 1.2;
      final len = (end - plaza).length;
      final n = (len / 0.28).round();
      for (var i = 0; i <= n; i++) {
        final f = i / n;
        final p = plaza * ((1 - f) * (1 - f)) + mid * (2 * f * (1 - f)) + end * (f * f);
        stones.addInstance(
          vm.Matrix4.translation(p + vm.Vector3(0, 0.06, 0))
            ..scaleByVector3(vm.Vector3(0.13 + rnd.nextDouble() * 0.04, 0.03, 0.13)),
        );
      }
    }
    scene.add(Node()..addComponent(InstancedMeshComponent(stones)));
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 0.7, topRadius: 0.7, height: 0.05, radialSegments: 32),
        _pbr(0.85, 0.76, 0.66),
        at: plaza + vm.Vector3(0, 0.06, 0),
      ),
    );

    // trees and rocks
    final trunk = _pbr(0.45, 0.3, 0.2), leaf = _pbr(0.18, 0.48, 0.24), leaf2 = _pbr(0.28, 0.58, 0.26);
    final rock = _pbr(0.55, 0.52, 0.56);
    for (var i = 0; i < 34; i++) {
      final a = rnd.nextDouble() * math.pi * 2, r = 1.2 + rnd.nextDouble() * 4.8;
      final p = vm.Vector3(math.cos(a) * r, 0, math.sin(a) * r);
      if (rides.any((rd) => (vm.Vector3(rd.x, 0, rd.z) - p).length < 1.1)) continue;
      if ((p - plaza).length < 1.0) continue;
      if (i % 5 == 0) {
        scene.add(
          _m(
            IcosphereGeometry(radius: 1, subdivisions: 1),
            rock,
            at: p + vm.Vector3(0, 0.12, 0),
            scale: vm.Vector3.all(0.18 + rnd.nextDouble() * 0.2),
          ),
        );
        continue;
      }
      final s = 0.6 + rnd.nextDouble() * 0.6;
      scene.add(
        _m(
          CylinderGeometry(bottomRadius: 0.05, topRadius: 0.04, height: 0.4),
          trunk,
          at: p + vm.Vector3(0, 0.2 * s, 0),
          scale: vm.Vector3.all(s),
        ),
      );
      scene.add(
        _m(
          SphereGeometry(radius: 1, segments: 16, rings: 10),
          i.isEven ? leaf : leaf2,
          at: p + vm.Vector3(0, 0.55 * s, 0),
          scale: vm.Vector3.all(0.3 * s),
        ),
      );
    }

    _buildRides();

    final r = await widget.brain.makeRig();
    r.showUmbrella = false;
    r.root.scale = vm.Vector3.all(0.6);
    scene.add(r.root);
    if (mounted) setState(() => rig = r);
  }

  void _buildRides() {
    final white = _pbr(0.92, 0.9, 0.95);
    final red = _pbr(0.85, 0.18, 0.2, rough: 0.5);
    for (final ride in rides) {
      final at = vm.Vector3(ride.x, 0.05, ride.z);
      switch (ride.name) {
        case 'Sky Coaster':
          final g = Node()..position = at;
          g.add(
            _m(
              TorusGeometry(radius: 0.65, tubeRadius: 0.05, radialSegments: 40),
              red,
              at: vm.Vector3(0, 0.85, 0),
              rot: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
            ),
          );
          g.add(
            _m(
              TorusGeometry(radius: 1.1, tubeRadius: 0.05, radialSegments: 48),
              red,
              at: vm.Vector3(0.0, 0.3, 0),
            ),
          );
          for (var i = 0; i < 6; i++) {
            final a = i / 6 * math.pi * 2;
            g.add(
              _m(
                CylinderGeometry(bottomRadius: 0.025, topRadius: 0.025, height: 0.3),
                white,
                at: vm.Vector3(math.cos(a) * 1.1, 0.15, math.sin(a) * 1.1),
              ),
            );
          }
          final car = Node();
          car.add(
            _m(
              CuboidGeometry(vm.Vector3(0.16, 0.1, 0.24)),
              _pbr(0.95, 0.8, 0.2),
              at: vm.Vector3(1.1, 0.38, 0),
            ),
          );
          g.add(car);
          spinners.add((car, 1.6));
          scene.add(g);
        case 'River Run':
          scene.add(
            _m(
              TorusGeometry(radius: 0.8, tubeRadius: 0.2, radialSegments: 40),
              _pbr(0.2, 0.55, 0.85, rough: 0.2),
              at: at + vm.Vector3(0, -0.05, 0),
            ),
          );
          final boat = Node()..position = at;
          boat.add(
            _m(
              CapsuleGeometry(radius: 0.08, height: 0.3),
              _pbr(0.5, 0.32, 0.2),
              at: vm.Vector3(0.8, 0.1, 0),
              rot: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
            ),
          );
          scene.add(boat);
          spinners.add((boat, -0.9));
        case 'Star Swing':
          final g = Node()..position = at;
          g.add(
            _m(
              CylinderGeometry(bottomRadius: 0.07, topRadius: 0.05, height: 1.5),
              white,
              at: vm.Vector3(0, 0.75, 0),
            ),
          );
          final top = Node()..position = vm.Vector3(0, 1.5, 0);
          top.add(
            Node(
              mesh: Mesh(
                stripedCone(0.75, 0.4, 8, vm.Vector4(0.55, 0.38, 0.95, 1), vm.Vector4(0.98, 0.96, 1, 1)),
                _pbr(1, 1, 1, rough: 0.6),
              ),
            ),
          );
          for (var i = 0; i < 8; i++) {
            final a = i / 8 * math.pi * 2;
            final sx = math.cos(a) * 0.62, sz = math.sin(a) * 0.62;
            top.add(
              _m(
                CylinderGeometry(bottomRadius: 0.008, topRadius: 0.008, height: 0.6),
                white,
                at: vm.Vector3(sx * 1.15, -0.3, sz * 1.15),
                rot: vm.Quaternion.axisAngle(vm.Vector3(-sz, 0, sx).normalized(), -0.35),
              ),
            );
            top.add(
              _m(
                CuboidGeometry(vm.Vector3(0.1, 0.04, 0.1)),
                _pbr(0.98, 0.75, 0.3),
                at: vm.Vector3(sx * 1.32, -0.6, sz * 1.32),
              ),
            );
          }
          g.add(top);
          spinners.add((top, 1.4));
          scene.add(g);
        case 'Moon Drop':
          final g = Node()..position = at;
          g.add(
            _m(
              CylinderGeometry(bottomRadius: 0.13, topRadius: 0.1, height: 2.6),
              white,
              at: vm.Vector3(0, 1.3, 0),
            ),
          );
          g.add(_m(SphereGeometry(radius: 0.22), unlit(2.0, 2.0, 1.7), at: vm.Vector3(0, 2.75, 0)));
          final ring = _m(
            TorusGeometry(radius: 0.22, tubeRadius: 0.07, radialSegments: 24),
            _pbr(0.45, 0.4, 0.95),
            at: vm.Vector3(0, 0.5, 0),
          );
          g.add(ring);
          dropRing = ring;
          scene.add(g);
        case 'Tidal Twist':
          final g = Node()..position = at;
          g.add(
            _m(
              CylinderGeometry(bottomRadius: 0.75, topRadius: 0.75, height: 0.08, radialSegments: 32),
              _pbr(0.2, 0.7, 0.75),
              at: vm.Vector3(0, 0.04, 0),
            ),
          );
          final spin = Node();
          for (var i = 0; i < 4; i++) {
            final a = i / 4 * math.pi * 2;
            spin.add(
              _m(
                CylinderGeometry(bottomRadius: 0.13, topRadius: 0.18, height: 0.2, radialSegments: 18),
                i.isEven ? _pbr(0.98, 0.5, 0.6) : _pbr(0.98, 0.85, 0.4),
                at: vm.Vector3(math.cos(a) * 0.45, 0.18, math.sin(a) * 0.45),
              ),
            );
          }
          g.add(spin);
          spinners.add((spin, 2.2));
          scene.add(g);
        case 'Comet Carousel':
          final g = Node()..position = at;
          g.add(
            _m(
              CylinderGeometry(bottomRadius: 0.9, topRadius: 0.9, height: 0.1, radialSegments: 40),
              white,
              at: vm.Vector3(0, 0.05, 0),
            ),
          );
          g.add(
            _m(
              CylinderGeometry(bottomRadius: 0.05, topRadius: 0.05, height: 0.8),
              _pbr(0.95, 0.8, 0.3),
              at: vm.Vector3(0, 0.45, 0),
            ),
          );
          g.add(
            Node(
              mesh: Mesh(
                stripedCone(1.05, 0.55, 10, vm.Vector4(0.95, 0.35, 0.45, 1), vm.Vector4(1, 0.97, 0.95, 1)),
                _pbr(1, 1, 1, rough: 0.6),
              ),
            )..position = vm.Vector3(0, 0.85, 0),
          );
          final horses = Node();
          for (var i = 0; i < 6; i++) {
            final a = i / 6 * math.pi * 2;
            horses.add(
              _m(
                SphereGeometry(radius: 0.09),
                i.isEven ? _pbr(0.6, 0.75, 1.0) : _pbr(1.0, 0.8, 0.5),
                at: vm.Vector3(math.cos(a) * 0.62, 0.32, math.sin(a) * 0.62),
              ),
            );
          }
          g.add(horses);
          spinners.add((horses, 0.9));
          scene.add(g);
      }
    }
  }

  void _go(Ride ride) {
    final r = rig;
    if (r == null) return;
    setState(() {
      lumiFrom = _lumiGround();
      lumiTo = vm.Vector3(ride.x, 0, ride.z) + vm.Vector3(math.sin(azimuth), 0, -math.cos(azimuth)) * 1.2;
      hopLen = (lumiTo - lumiFrom).length;
      hopT = 0;
      heading = ride;
      arrived = false;
    });
  }

  vm.Vector3 _lumiGround() {
    if (hopT >= 1) return lumiTo.clone();
    return lumiFrom + (lumiTo - lumiFrom) * hopT;
  }

  void _tick(double dt) {
    t += dt;
    camera = _cam();
    for (final (n, speed) in spinners) {
      n.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), t * speed);
    }
    final ring = dropRing;
    if (ring != null) {
      final ph = (t % 5) / 5;
      final y = ph < 0.6 ? 0.5 + ph / 0.6 * 1.9 : 2.4 - math.pow((ph - 0.6) / 0.4, 2) * 1.9;
      ring.position = vm.Vector3(0, y.toDouble(), 0);
    }
    final r = rig;
    if (r == null) return;
    var hopH = 0.0;
    if (hopT < 1) {
      hopT = math.min(1, hopT + dt * 1.9 / math.max(0.5, hopLen));
      final hops = math.max(1, (hopLen / 0.8).round());
      final ph = (hopT * hops) % 1;
      hopH = math.sin(ph * math.pi) * 0.35;
      r.squashY = ph < 0.08 || ph > 0.92 ? 0.82 : 1.08;
      if (hopT >= 1) {
        r.squashY = 1;
        arrived = true;
        setState(() {});
      }
    }
    final g = _lumiGround();
    r.root.position = g + vm.Vector3(0, 0.45 + hopH + math.sin(t * 2) * 0.03, 0);
    final dir = lumiTo - lumiFrom;
    // The rig faces -Z, so turn it toward the hop direction, or the camera when idle.
    final yaw = hopT < 1 && dir.length > 0.01 ? math.atan2(-dir.x, -dir.z) : -azimuth;
    // Lean back a little so the face reads from the high map camera.
    r.root.rotation =
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw) *
        vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), hopT < 1 ? 0.15 : elevation * 0.55);
    r.face = arrived ? Face.happy : Face.idle;
    r.handsUp = arrived ? 1 : 0;
    r.update(dt);
    frame.value++;
  }

  @override
  void dispose() {
    frame.dispose();
    super.dispose();
  }

  double _scaleStart = 1;
  double _rotStart = 0;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final name = rig?.style.name ?? widget.brain.rig?.style.name ?? 'Lumi';
    final best = rides.reduce((a, b) => a.wait <= b.wait ? a : b);
    final shown = heading ?? best;
    return Scaffold(
      backgroundColor: const Color(0xFF1F5E86),
      body: LayoutBuilder(
        builder: (context, c) {
          size = Size(c.maxWidth, c.maxHeight);
          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF2A6E96), Color(0xFF1B4E75)],
                    ),
                  ),
                ),
              ),
              if (rig != null)
                Positioned.fill(
                  child: GestureDetector(
                    onScaleStart: (d) {
                      _scaleStart = distance;
                      _rotStart = azimuth;
                    },
                    onScaleUpdate: (d) {
                      if (d.pointerCount >= 2) {
                        distance = (_scaleStart / d.scale).clamp(6.0, 22.0);
                        azimuth = _rotStart - d.rotation;
                      } else {
                        // pan along the ground relative to the view
                        final f = vm.Vector3(-math.sin(azimuth), 0, math.cos(azimuth));
                        final rgt = vm.Vector3(math.cos(azimuth), 0, math.sin(azimuth));
                        final k = distance / 520;
                        target += rgt * (-d.focalPointDelta.dx * k) + f * (d.focalPointDelta.dy * k * 1.4);
                        target.x = target.x.clamp(-5.0, 5.0);
                        target.z = target.z.clamp(-5.0, 5.0);
                      }
                    },
                    child: SceneView(scene, cameraBuilder: (_) => camera, onTick: (_, dt) => _tick(dt)),
                  ),
                )
              else
                const Center(child: CircularProgressIndicator(color: Colors.white)),
              // floating wait-time tags
              if (rig != null)
                ValueListenableBuilder(
                  valueListenable: frame,
                  builder: (_, _, _) {
                    final proj = Projector(camera, size);
                    final tags = <(double, Widget)>[];
                    for (final ride in rides) {
                      final h = ride.name == 'Moon Drop' ? 3.1 : 1.9;
                      final p = proj(ride.x, h, ride.z);
                      if (p == null ||
                          p.dx < -80 ||
                          p.dx > size.width + 80 ||
                          p.dy < 40 ||
                          p.dy > size.height - 90) {
                        continue;
                      }
                      final depth = (camera.position - vm.Vector3(ride.x, h, ride.z)).length;
                      tags.add((
                        depth,
                        Positioned(
                          left: p.dx - 58,
                          top: p.dy - 44,
                          child: _RideTag(ride: ride, onGo: () => _go(ride), selected: heading == ride),
                        ),
                      ));
                    }
                    tags.sort((a, b) => b.$1.compareTo(a.$1));
                    return Stack(children: [for (final t in tags) t.$2]);
                  },
                ),
              Positioned(
                top: pad.top + 4,
                left: 4,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    Text('Park map', style: Pd.t(15, w: FontWeight.w700)),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: pad.bottom + 14,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xF0141838),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Pd.stroke),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            center: Alignment(-0.3, -0.4),
                            colors: [Color(0xFFCDE7FF), Color(0xFF5EA8FF)],
                          ),
                        ),
                        child: const Icon(Icons.face_retouching_natural, size: 18, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              heading == null
                                  ? 'Shortest wait right now'
                                  : arrived
                                  ? '$name made it to ${heading!.name}!'
                                  : '$name is hopping over…',
                              style: Pd.t(10.5, c: Pd.textDim),
                            ),
                            const SizedBox(height: 2),
                            Text('${shown.name} · ${shown.wait} min', style: Pd.t(13.5, w: FontWeight.w700)),
                          ],
                        ),
                      ),
                      PillButton(
                        label: heading == null ? 'Send $name' : 'Take me',
                        onTap: () {
                          if (heading == null) {
                            _go(best);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Walking directions to ${heading!.name} · ${(heading!.wait / 2).ceil()} min walk',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ],
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

class _RideTag extends StatelessWidget {
  const _RideTag({required this.ride, required this.onGo, required this.selected});
  final Ride ride;
  final VoidCallback onGo;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final waitColor = ride.wait <= 5
        ? const Color(0xFF7CF0A8)
        : ride.wait <= 15
        ? const Color(0xFFFFD27A)
        : const Color(0xFFFF8A80);
    return GestureDetector(
      onTap: onGo,
      child: Container(
        width: 116,
        padding: const EdgeInsets.fromLTRB(8, 5, 5, 5),
        decoration: BoxDecoration(
          color: const Color(0xF01A1F45),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? const Color(0xFF8FD3FF) : const Color(0x22FFFFFF)),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ride.kind, style: Pd.eyebrow(Pd.textFaint).copyWith(fontSize: 7)),
                  Text(
                    ride.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Pd.t(10, w: FontWeight.w700),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(color: waitColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 3),
                      Text('${ride.wait} min', style: Pd.t(8.5, c: Pd.textDim)),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF5B8CFF)),
              child: Icon(
                selected ? Icons.check_rounded : Icons.near_me_rounded,
                size: 13,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
