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

// The fountain plaza is the hub every path leads from; Lumi waits just
// inside the entrance gate, at the south edge nearest the camera.
final _fountain = vm.Vector3.zero();
final _gate = vm.Vector3(0, 0, -3.7);
final _start = vm.Vector3(0, 0, -3.0);

/// A flat strip [width] wide following [pts] on the ground, for the grout
/// under a cobbled path.
MeshGeometry _ribbon(List<vm.Vector3> pts, double width) {
  final pos = <double>[], nor = <double>[];
  final idx = <int>[];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[math.max(0, i - 1)], b = pts[math.min(pts.length - 1, i + 1)];
    final side = (b - a).cross(vm.Vector3(0, 1, 0)).normalized() * (width / 2);
    for (final q in [pts[i] - side, pts[i] + side]) {
      pos.addAll([q.x, q.y, q.z]);
      nor.addAll([0, 1, 0]);
    }
    if (i > 0) {
      final k = i * 2;
      idx.addAll([k - 2, k, k - 1, k - 1, k, k + 1]);
    }
  }
  return MeshGeometry.fromArrays(
    positions: Float32List.fromList(pos),
    normals: Float32List.fromList(nor),
    indices: idx,
  );
}

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
  // The camera opens on the whole island, then dollies in and follows
  // Lumi when it hops off, like the original. Any pan or pinch hands it
  // to the user.
  double azimuth = 0.1, elevation = 0.85, distance = 25;
  vm.Vector3 target = vm.Vector3(0, 0, 1.1);
  static const _azGoal = 0.1;
  double _elGoal = 0.85, _distGoal = 25;
  vm.Vector3 _targetGoal = vm.Vector3(0, 0, 1.1);
  bool _userCam = false;
  late PerspectiveCamera camera = _cam();

  // animated rides
  final spinners = <(Node, double)>[];

  // Wait-time tags: live widgets on 3D cards above each ride.
  final tags = <(Ride, Node)>[];
  final selected = ValueNotifier<Ride?>(null);
  static const _tagSize = Size(120, 50), _tagHeight = 0.74;
  Node? dropRing;

  // Lumi hopping
  vm.Vector3 lumiFrom = _start.clone();
  vm.Vector3 lumiTo = _start.clone();
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
    return PerspectiveCamera(fovRadiansY: 40 * vm.degrees2Radians, position: eye, target: target, fovFar: 120);
  }

  Future<void> _build() async {
    await Scene.initializeStaticResources();
    // An evening look like the original's: a night sky and dark water
    // around a saturated island, soft shadows and contact darkening, warm
    // lamps that bloom, and a tilt-shift blur that makes the park a toy.
    scene.environmentSettings = EnvironmentSettings(
      skybox: Skybox(
        GradientSkySource(
          zenithColor: vm.Vector3(0.012, 0.018, 0.06),
          horizonColor: vm.Vector3(0.04, 0.06, 0.16),
          groundColor: vm.Vector3(0.02, 0.03, 0.08),
          sunColor: vm.Vector3.zero(),
        ),
      ),
      environmentIntensity: 0.55,
      toneMapping: ToneMappingMode.pbrNeutral,
      exposure: 1.0,
      colorGradingEnabled: true,
      saturation: 1.05,
      contrast: 1.05,
      bloomEnabled: true,
      bloomThreshold: 1.0,
      bloomIntensity: 0.3,
      bloomScatter: 0.6,
      ambientOcclusionEnabled: true,
      ambientOcclusionRadius: 0.35,
      ambientOcclusionIntensity: 1.2,
      vignetteEnabled: true,
      vignetteIntensity: 0.35,
      // The blue evening haze the original lays over the whole park.
      fogEnabled: true,
      fogColor: vm.Vector3(0.22, 0.3, 0.55),
      fogDensity: 0.012,
      fogMaxOpacity: 0.35,
    );
    scene.depthOfField
      ..enabled = true
      ..fStop = 0.6
      ..blurScale = 10
      ..quality = DepthOfFieldQuality.medium;
    final sun = Node();
    sun.addComponent(
      // The component ignores DirectionalLight.direction, so aim it here.
      DirectionalLightComponent.aimed(
        DirectionalLight(
          intensity: 1.7,
          color: vm.Vector3(1, 0.86, 0.72),
          castsShadow: true,
          shadowMaxDistance: 40,
          shadowCascadeCount: 2,
          shadowSoftness: 0.15,
        ),
        vm.Vector3(0.5, -0.8, 0.6),
      ),
    );
    scene.add(sun);

    // water and island
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 45, topRadius: 45, height: 0.2, radialSegments: 96),
        _pbr(0.012, 0.018, 0.06, rough: 0.35),
        at: vm.Vector3(0, -0.45, 0),
      ),
    );
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 5.9, topRadius: 5.6, height: 0.7, radialSegments: 64),
        _pbr(0.3, 0.24, 0.3),
        at: vm.Vector3(0, -0.36, 0),
      ),
    );
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 5.5, topRadius: 5.5, height: 0.1, radialSegments: 64),
        _pbr(0.11, 0.42, 0.27),
        at: vm.Vector3(0, 0.0, 0),
      ),
    );
    final rnd = math.Random(4);
    // Cobbled paths: a ring round the fountain and a lane from it to every
    // ride and to the gate, each a dark grout strip set with stones.
    final cobbles = InstancedMesh(
      geometry: CuboidGeometry(vm.Vector3(1, 1, 1)),
      material: _pbr(0.5, 0.4, 0.35, rough: 0.9),
    );
    final grout = _pbr(0.1, 0.075, 0.07);
    final fountain = _fountain;
    final pathPts = <vm.Vector3>[];
    void stone(vm.Vector3 p, double yaw, double w) {
      final shade = 0.78 + rnd.nextDouble() * 0.4;
      cobbles.addInstance(
        vm.Matrix4.translation(p + vm.Vector3(0, 0.07, 0))
          ..rotateY(yaw + (rnd.nextDouble() - 0.5) * 0.25)
          ..scaleByVector3(vm.Vector3(w, 0.035, 0.085 + rnd.nextDouble() * 0.02)),
        color: vm.Vector4(shade, shade * (0.96 + rnd.nextDouble() * 0.06), shade, 1),
      );
    }

    void lane(vm.Vector3 from, vm.Vector3 to, {double width = 0.56}) {
      final dir = (to - from).normalized();
      final bend = dir.cross(vm.Vector3(0, 1, 0)) * ((rnd.nextDouble() - 0.5) * 0.9);
      final mid = (from + to) * 0.5 + bend;
      final len = (to - from).length;
      final n = (len / 0.11).round();
      final pts = <vm.Vector3>[];
      for (var i = 0; i <= n; i++) {
        final f = i / n;
        pts.add(from * ((1 - f) * (1 - f)) + mid * (2 * f * (1 - f)) + to * (f * f));
      }
      scene.add(_m(_ribbon(pts.map((q) => q + vm.Vector3(0, 0.055, 0)).toList(), width + 0.05), grout));
      for (var i = 0; i < pts.length; i++) {
        final tdir = pts[math.min(pts.length - 1, i + 1)] - pts[math.max(0, i - 1)];
        final yaw = math.atan2(tdir.x, tdir.z);
        final side = tdir.cross(vm.Vector3(0, 1, 0)).normalized();
        final across = (width / 0.11).floor();
        final off = i.isEven ? 0.0 : 0.055;
        for (var k = 0; k < across; k++) {
          final o = -width / 2 + 0.055 + k * 0.11 + off;
          if (o > width / 2 - 0.04) continue;
          stone(pts[i] + side * o, yaw + math.pi / 2, 0.09);
        }
        pathPts.add(pts[i]);
      }
    }

    // the plaza ring
    scene.add(
      _m(RingGeometry(innerRadius: 0.5, outerRadius: 1.3, segments: 48), grout, at: fountain + vm.Vector3(0, 0.055, 0)),
    );
    for (var r = 0.58; r < 1.27; r += 0.11) {
      final n = (2 * math.pi * r / 0.11).floor();
      final phase = rnd.nextDouble();
      for (var i = 0; i < n; i++) {
        final a = (i + phase) / n * math.pi * 2;
        final p = fountain + vm.Vector3(math.cos(a) * r, 0, math.sin(a) * r);
        stone(p, -a, 0.09);
        pathPts.add(p);
      }
    }
    for (final ride in rides) {
      final end = vm.Vector3(ride.x, 0, ride.z);
      final dir = (end - fountain).normalized();
      lane(fountain + dir * 1.25, end - dir * 0.95);
    }
    lane(fountain + vm.Vector3(0, 0, -1.25), _gate + vm.Vector3(0, 0, 0.1), width: 0.66);
    scene.add(Node()..addComponent(InstancedMeshComponent(cobbles)));

    // A tiered fountain in the middle of the plaza.
    final marble = _pbr(0.78, 0.74, 0.8, rough: 0.5);
    final water = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.1, 0.4, 0.85, 1)
      ..roughnessFactor = 0.1
      ..metallicFactor = 0
      ..emissiveFactor = vm.Vector4(0.03, 0.15, 0.4, 1);
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 0.5, topRadius: 0.46, height: 0.14, radialSegments: 32),
        marble,
        at: fountain + vm.Vector3(0, 0.12, 0),
      ),
    );
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 0.4, topRadius: 0.4, height: 0.02, radialSegments: 32),
        water,
        at: fountain + vm.Vector3(0, 0.19, 0),
      ),
    );
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 0.06, topRadius: 0.05, height: 0.3, radialSegments: 12),
        marble,
        at: fountain + vm.Vector3(0, 0.33, 0),
      ),
    );
    scene.add(
      _m(
        CylinderGeometry(bottomRadius: 0.08, topRadius: 0.18, height: 0.06, radialSegments: 24),
        marble,
        at: fountain + vm.Vector3(0, 0.5, 0),
      ),
    );
    scene.add(_m(SphereGeometry(radius: 0.07, segments: 12, rings: 8), water, at: fountain + vm.Vector3(0, 0.56, 0)));

    // The entrance gate: two round towers with candy domes and a red arch.
    final towerWall = _pbr(0.9, 0.84, 0.86, rough: 0.6);
    final dome = _pbr(0.9, 0.22, 0.32, rough: 0.5);
    for (final x in [-0.62, 0.62]) {
      final at = _gate + vm.Vector3(x, 0, 0);
      scene.add(
        _m(
          CylinderGeometry(bottomRadius: 0.3, topRadius: 0.28, height: 0.8, radialSegments: 24),
          towerWall,
          at: at + vm.Vector3(0, 0.4, 0),
        ),
      );
      scene.add(
        _m(
          SphereGeometry(radius: 1, segments: 20, rings: 12),
          dome,
          at: at + vm.Vector3(0, 0.82, 0),
          scale: vm.Vector3(0.34, 0.3, 0.34),
        ),
      );
      scene.add(
        _m(TorusGeometry(radius: 0.3, tubeRadius: 0.03, radialSegments: 24), dome, at: at + vm.Vector3(0, 0.62, 0)),
      );
    }
    scene.add(_m(CuboidGeometry(vm.Vector3(1.0, 0.08, 0.1)), _pbr(0.8, 0.14, 0.2), at: _gate + vm.Vector3(0, 0.7, 0)));
    // a picket fence along the south shore either side of the gate
    final pickets = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(1, 1, 1)), material: _pbr(0.92, 0.9, 0.88));
    for (var i = 0; i < 26; i++) {
      final a = -math.pi / 2 + (i < 13 ? -1 : 1) * (0.2 + (i % 13) * 0.045);
      final p = vm.Vector3(math.cos(a) * 5.1, 0, math.sin(a) * 5.1);
      pickets.addInstance(
        vm.Matrix4.translation(p + vm.Vector3(0, 0.12, 0))
          ..rotateY(-a)
          ..scaleByVector3(vm.Vector3(0.03, 0.24, 0.03)),
      );
      pickets.addInstance(
        vm.Matrix4.translation(p + vm.Vector3(0, 0.18, 0))
          ..rotateY(-a + math.pi / 2)
          ..scaleByVector3(vm.Vector3(0.012, 0.025, 0.27)),
      );
    }
    scene.add(Node()..addComponent(InstancedMeshComponent(pickets)));

    // Trees, bushes and rocks, instanced by material. Canopies are one or
    // two soft blobs in a few greens, with the odd blossom tree.
    InstancedMesh inst(Geometry g, fs.Material m) => InstancedMesh(geometry: g, material: m);
    final blob = SphereGeometry(radius: 1, segments: 16, rings: 10);
    final trunks = inst(CylinderGeometry(bottomRadius: 0.05, topRadius: 0.04, height: 0.4), _pbr(0.22, 0.12, 0.07));
    final canopies = [
      inst(blob, _pbr(0.04, 0.33, 0.24)),
      inst(blob, _pbr(0.12, 0.48, 0.27)),
      inst(blob, _pbr(0.28, 0.55, 0.14)),
      inst(blob, _pbr(0.85, 0.42, 0.58)),
      inst(blob, _pbr(0.85, 0.38, 0.1)),
    ];
    final rocks = inst(IcosphereGeometry(radius: 1, subdivisions: 1), _pbr(0.4, 0.33, 0.4));
    bool clear(vm.Vector3 p, double r) =>
        !rides.any((rd) => (vm.Vector3(rd.x, 0, rd.z) - p).length < 1.0 + r) &&
        (p - fountain).length > 1.4 + r &&
        (p - _gate).length > 1.1 + r &&
        !pathPts.any((q) => (q - p).length < 0.22 + r);
    for (var i = 0; i < 110; i++) {
      final a = rnd.nextDouble() * math.pi * 2, r = 1.0 + math.sqrt(rnd.nextDouble()) * 4.2;
      final p = vm.Vector3(math.cos(a) * r, 0, math.sin(a) * r);
      final s = 0.45 + rnd.nextDouble() * 0.6;
      if (!clear(p, 0.25 * s)) continue;
      if (i % 9 == 0) {
        rocks.addInstance(
          vm.Matrix4.translation(p + vm.Vector3(0, 0.1, 0))
            ..scaleByVector3(vm.Vector3.all(0.14 + rnd.nextDouble() * 0.18)),
        );
        continue;
      }
      final pick = rnd.nextDouble();
      final c =
          canopies[pick < 0.04
              ? 3
              : pick < 0.07
              ? 4
              : rnd.nextInt(3)];
      trunks.addInstance(vm.Matrix4.translation(p + vm.Vector3(0, 0.2 * s, 0))..scaleByVector3(vm.Vector3.all(s)));
      c.addInstance(
        vm.Matrix4.translation(p + vm.Vector3(0, 0.55 * s, 0))..scaleByVector3(vm.Vector3(0.3, 0.27, 0.3) * s),
      );
      if (rnd.nextBool()) {
        final off = vm.Vector3(rnd.nextDouble() - 0.5, 0, rnd.nextDouble() - 0.5).normalized() * 0.2 * s;
        c.addInstance(
          vm.Matrix4.translation(p + off + vm.Vector3(0, 0.42 * s, 0))..scaleByVector3(vm.Vector3.all(0.2 * s)),
        );
      }
    }
    // Big boulders round the rim of the island.
    for (var i = 0; i < 26; i++) {
      final a = i / 26 * math.pi * 2 + rnd.nextDouble() * 0.12;
      final r = 5.35 + rnd.nextDouble() * 0.3;
      final sz = 0.3 + rnd.nextDouble() * 0.3;
      rocks.addInstance(
        vm.Matrix4.translation(vm.Vector3(math.cos(a) * r, -0.05, math.sin(a) * r))
          ..rotateY(rnd.nextDouble() * 6)
          ..scaleByVector3(vm.Vector3(sz * 1.3, sz * 0.8, sz)),
      );
    }
    for (final m in [trunks, ...canopies, rocks]) {
      scene.add(Node()..addComponent(InstancedMeshComponent(m)));
    }

    // Lamp posts along the paths and round the shore, and lily pads.
    final pole = _pbr(0.04, 0.04, 0.07, rough: 0.5);
    final lampGlow = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(1, 0.85, 0.5, 1)
      ..emissiveFactor = vm.Vector4(5, 3.4, 1.4, 1);
    final lamps = <vm.Vector3>[];
    for (final ride in [...rides.map((r) => vm.Vector3(r.x, 0, r.z)), _gate]) {
      final dir = (ride - fountain).normalized();
      final side = dir.cross(vm.Vector3(0, 1, 0));
      lamps.add(fountain + dir * 1.45 + side * 0.4);
    }
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * math.pi * 2 + 0.2;
      lamps.add(vm.Vector3(math.cos(a) * 5.2, 0, math.sin(a) * 5.2));
    }
    for (final p in lamps) {
      scene.add(
        _m(CylinderGeometry(bottomRadius: 0.025, topRadius: 0.02, height: 0.5), pole, at: p + vm.Vector3(0, 0.25, 0)),
      );
      scene.add(_m(SphereGeometry(radius: 0.06, segments: 10, rings: 6), lampGlow, at: p + vm.Vector3(0, 0.53, 0)));
    }
    // A few warm pools of light on the grass.
    for (final p in [fountain, _gate, lamps[0], lamps[3]]) {
      scene.add(
        Node()
          ..position = p + vm.Vector3(0, 0.7, 0)
          ..addComponent(PointLightComponent(PointLight(color: vm.Vector3(1, 0.75, 0.5), intensity: 0.7, range: 1.8))),
      );
    }
    final pad = _pbr(0.06, 0.32, 0.12, rough: 0.6);
    for (var i = 0; i < 22; i++) {
      final a = rnd.nextDouble() * math.pi * 2, r = 7.2 + rnd.nextDouble() * 5;
      scene.add(
        _m(
          CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 16),
          pad,
          at: vm.Vector3(math.cos(a) * r, -0.34, math.sin(a) * r),
          scale: vm.Vector3(0.12 + rnd.nextDouble() * 0.1, 0.02, 0.12 + rnd.nextDouble() * 0.1),
        ),
      );
    }

    _buildRides();
    _buildTags();

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
          g.add(_m(TorusGeometry(radius: 1.1, tubeRadius: 0.05, radialSegments: 48), red, at: vm.Vector3(0.0, 0.3, 0)));
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
          car.add(_m(CuboidGeometry(vm.Vector3(0.16, 0.1, 0.24)), _pbr(0.95, 0.8, 0.2), at: vm.Vector3(1.1, 0.38, 0)));
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
            _m(CylinderGeometry(bottomRadius: 0.07, topRadius: 0.05, height: 1.5), white, at: vm.Vector3(0, 0.75, 0)),
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
            _m(CylinderGeometry(bottomRadius: 0.13, topRadius: 0.1, height: 2.6), white, at: vm.Vector3(0, 1.3, 0)),
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

  /// One card per ride, hosting the real tag widget through Flutter Scene's
  /// `WidgetComponent`: it sits in the map in perspective, shrinks with
  /// distance and hides behind the Moon Drop tower like any other object.
  void _buildTags() {
    for (final ride in rides) {
      final h = ride.name == 'Moon Drop' ? 3.1 : 1.9;
      final node = Node(name: 'tag ${ride.name}')..position = vm.Vector3(ride.x, h + _tagHeight / 2, ride.z);
      node.addComponent(
        WidgetComponent(
          size: _tagSize,
          pixelRatio: 3,
          worldHeight: _tagHeight,
          geometry: cardQuad(_tagHeight * _tagSize.width / _tagSize.height, _tagHeight),
          // Taps are hit-tested against the cards by the map itself, so a
          // drag that starts on a tag still pans the map.
          input: WidgetInput.manual,
          update: const WidgetUpdatePolicy.interval(Duration(milliseconds: 200)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder(
              valueListenable: selected,
              builder: (_, sel, _) => _RideTag(ride: ride, onGo: () {}, selected: sel == ride),
            ),
          ),
        ),
      );
      scene.add(node);
      tags.add((ride, node));
    }
  }

  /// Turns the cards to face the camera, tipped back a little less than
  /// the view so they read as cards standing in the park.
  void _faceTags() {
    final q =
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -azimuth) *
        vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), elevation * 0.8);
    for (final (_, n) in tags) {
      n.rotation = q;
    }
  }

  /// The ride whose card is under [p], nearest first.
  Ride? _tagAt(Offset p) {
    final proj = Projector(camera, size);
    Ride? best;
    var bestDepth = double.infinity;
    for (final (ride, n) in tags) {
      final c = n.position;
      final center = proj(c.x, c.y, c.z);
      final top = proj(c.x, c.y + _tagHeight / 2, c.z);
      if (center == null || top == null) continue;
      final hh = (center - top).distance;
      final hw = hh * _tagSize.width / _tagSize.height;
      if ((p.dx - center.dx).abs() > hw || (p.dy - center.dy).abs() > hh) continue;
      final depth = (camera.position - c).length;
      if (depth < bestDepth) {
        bestDepth = depth;
        best = ride;
      }
    }
    return best;
  }

  void _go(Ride ride) {
    final r = rig;
    if (r == null) return;
    selected.value = ride;
    _userCam = false;
    _distGoal = 16.5;
    _elGoal = 0.9;
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
    if (!_userCam) {
      // Ease towards the overview, or after Lumi once it sets off.
      // Keep the plaza in frame by leaning the target back towards it.
      if (heading != null) _targetGoal = _lumiGround() * 0.7 + vm.Vector3(0, 0, 0.9);
      final k = 1 - math.exp(-dt * 1.4);
      target += (_targetGoal - target) * k;
      distance += (_distGoal - distance) * k;
      elevation += (_elGoal - elevation) * k;
      azimuth += (_azGoal - azimuth) * k;
    }
    camera = _cam();
    scene.depthOfField
      ..focusDistance = distance
      ..blurScale = (distance / 2.2).clamp(4.0, 10.0);
    _faceTags();
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
    selected.dispose();
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
      backgroundColor: const Color(0xFF0B1030),
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
                      colors: [Color(0xFF0B1030), Color(0xFF141B45)],
                    ),
                  ),
                ),
              ),
              if (rig != null)
                Positioned.fill(
                  child: GestureDetector(
                    onTapUp: (d) {
                      final ride = _tagAt(d.localPosition);
                      if (ride != null) _go(ride);
                    },
                    onScaleStart: (d) {
                      _userCam = true;
                      _scaleStart = distance;
                      _rotStart = azimuth;
                    },
                    onScaleUpdate: (d) {
                      if (d.pointerCount >= 2) {
                        distance = (_scaleStart / d.scale).clamp(8.0, 40.0);
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
              child: Icon(selected ? Icons.check_rounded : Icons.near_me_rounded, size: 13, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
