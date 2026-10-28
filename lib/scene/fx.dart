import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// What a spark looks like over its life (see `sparks.fmat`).
enum SparkKind { spark, glitter, flash, smoke, comet, star, ring, glow }

/// Collects sparks and packs them into one static mesh for the `sparks.fmat`
/// material, which moves them on the GPU from a single `time` parameter.
class SparkBuilder {
  final _pos = <double>[];
  final _vel = <double>[];
  final _uv = <double>[];
  final _uv1 = <double>[];
  final _col = <double>[];
  final _prm = <double>[];
  final _idx = <int>[];
  int _count = 0;

  int get count => _count;

  /// Adds one spark launched from [origin] with [velocity] at [start] that
  /// lives [life] seconds. [color] is HDR light; [size] is its half width.
  /// It slows with [drag], falls with [gravity], and draws a streak [trail]
  /// seconds long.
  void add({
    required vm.Vector3 origin,
    vm.Vector3? velocity,
    required double start,
    required double life,
    required vm.Vector3 color,
    double size = 0.1,
    double drag = 0,
    double gravity = 0,
    double trail = 0,
    SparkKind kind = SparkKind.spark,
  }) {
    final v = velocity ?? vm.Vector3.zero();
    final base = _count * 4;
    const corners = [-1.0, 0.0, 1.0, 0.0, -1.0, 1.0, 1.0, 1.0];
    for (var k = 0; k < 4; k++) {
      _pos.addAll([origin.x, origin.y, origin.z]);
      _vel.addAll([v.x, v.y, v.z]);
      _uv.addAll([corners[k * 2], corners[k * 2 + 1]]);
      _uv1.addAll([start, life]);
      _col.addAll([color.x, color.y, color.z, size]);
      _prm.addAll([drag, gravity, trail, kind.index.toDouble()]);
    }
    _idx.addAll([base, base + 1, base + 2, base + 1, base + 3, base + 2]);
    _count++;
  }

  /// The packed mesh. [bounds] must cover everywhere the sparks fly, since
  /// the engine only sees their launch points.
  Mesh build(Material material, vm.Aabb3 bounds) {
    final geometry = MeshGeometry.fromArrays(
      positions: Float32List.fromList(_pos),
      normals: Float32List.fromList(_vel),
      texCoords: Float32List.fromList(_uv),
      texCoords1: Float32List.fromList(_uv1),
      colors: Float32List.fromList(_col),
      tangents: Float32List.fromList(_prm),
      indices: _idx,
      bounds: bounds,
    );
    return Mesh(geometry, material);
  }
}

/// A one-shot burst of sparks in a scene: built once, aged by [update], and
/// removed when every spark has died.
class SparkBurst {
  SparkBurst(this.node, this.material, this.duration);
  final Node node;
  final PreprocessedMaterial material;
  final double duration;
  double age = 0;
  bool get done => age > duration;

  void update(double dt) {
    age += dt;
    material.parameters.setFloat('time', age);
  }
}

/// The home screen's 3D effects around Lumi: trick sparkles, the friend
/// swap shockwave, key sparkles. Each burst is a [SparkBurst] with its own
/// material instance, so its clock starts at zero.
class HomeFx {
  HomeFx(this.scene);
  final Scene scene;
  final _live = <SparkBurst>[];
  final _rnd = math.Random();

  static final _bounds = vm.Aabb3.minMax(vm.Vector3.all(-30), vm.Vector3.all(30));

  Future<SparkBurst> _spawn(vm.Vector3 at, SparkBuilder b, double duration) async {
    final mat = await loadFmatMaterial('assets/materials/sparks.fmat');
    final node = Node(name: 'fx', mesh: b.build(mat, _bounds))..position = at;
    final burst = SparkBurst(node, mat, duration);
    mat.parameters.setFloat('time', 0);
    scene.add(node);
    _live.add(burst);
    return burst;
  }

  void update(double dt) {
    for (final b in _live) {
      b.update(dt);
    }
    for (final b in _live.where((b) => b.done).toList()) {
      b.node.detach();
      _live.remove(b);
    }
  }

  vm.Vector3 _sphere() {
    final y = _rnd.nextDouble() * 2 - 1;
    final a = _rnd.nextDouble() * math.pi * 2;
    final r = math.sqrt(1 - y * y);
    return vm.Vector3(math.cos(a) * r, y, math.sin(a) * r);
  }

  /// A golden "ta-da": a fountain of glittering sparks that arcs up and
  /// rains back down around Lumi.
  void sparkle(vm.Vector3 at, vm.Vector3 color, {int count = 70, double power = 1}) {
    final b = SparkBuilder()
      ..add(origin: vm.Vector3.zero(), start: 0, life: 0.6, color: color * 1.6, size: 1.1, kind: SparkKind.flash);
    for (var i = 0; i < count; i++) {
      final d = _sphere();
      d.y = d.y.abs() * 0.8 + 0.35;
      d.z *= 0.5;
      final speed = (2.6 + _rnd.nextDouble() * 2.8) * power;
      final c = _rnd.nextDouble() < 0.3 ? vm.Vector3(4, 3.8, 3.4) : color * (1.5 + _rnd.nextDouble() * 1.5);
      b.add(
        origin: d * 0.25,
        velocity: d.normalized() * speed,
        start: _rnd.nextDouble() * 0.12,
        life: 0.9 + _rnd.nextDouble() * 0.8,
        color: c,
        size: 0.022 + _rnd.nextDouble() * 0.02,
        drag: 2.2,
        gravity: -5.5,
        trail: 0.07,
        kind: _rnd.nextDouble() < 0.5 ? SparkKind.glitter : SparkKind.spark,
      );
    }
    _spawn(at, b, 1.9);
  }

  /// The friend swap: a ring that punches outwards, warp streaks flying past
  /// the screen edges, and a handful of twinkles left behind.
  void shockwave(vm.Vector3 at, vm.Vector3 color, {double radius = 1.5}) {
    final white = vm.Vector3(3.2, 3.2, 3.4);
    final b = SparkBuilder()
      ..add(origin: vm.Vector3.zero(), start: 0, life: 0.75, color: color * 2.2 + white * 0.3, size: radius, kind: SparkKind.ring)
      ..add(origin: vm.Vector3.zero(), start: 0, life: 0.45, color: white * 0.45, size: 0.9, kind: SparkKind.flash);
    for (var i = 0; i < 90; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final d = vm.Vector3(math.cos(a), math.sin(a), (_rnd.nextDouble() - 0.5) * 0.6);
      final r0 = 0.5 + _rnd.nextDouble() * 1.2;
      b.add(
        origin: d * r0,
        velocity: d * (9 + _rnd.nextDouble() * 9),
        start: _rnd.nextDouble() * 0.25,
        life: 0.35 + _rnd.nextDouble() * 0.35,
        color: (_rnd.nextBool() ? color * 1.8 : white) * (0.7 + _rnd.nextDouble() * 0.6),
        size: 0.012 + _rnd.nextDouble() * 0.012,
        drag: 0.6,
        trail: 0.05,
      );
    }
    for (var i = 0; i < 24; i++) {
      final d = _sphere()..z *= 0.3;
      b.add(
        origin: d * (0.2 + _rnd.nextDouble() * 0.9),
        velocity: d * 0.4,
        start: 0.1 + _rnd.nextDouble() * 0.3,
        life: 0.6 + _rnd.nextDouble() * 0.6,
        color: white * (0.8 + _rnd.nextDouble()),
        size: 0.05 + _rnd.nextDouble() * 0.05,
        drag: 1.5,
        kind: SparkKind.star,
      );
    }
    _spawn(at, b, 1.3);
  }

  /// A small puff of sparks, for a note being eaten.
  void puff(vm.Vector3 at, vm.Vector3 color) {
    final b = SparkBuilder();
    for (var i = 0; i < 18; i++) {
      final d = _sphere()..z *= 0.4;
      b.add(
        origin: d * 0.05,
        velocity: d * (1.2 + _rnd.nextDouble() * 1.4),
        start: 0,
        life: 0.4 + _rnd.nextDouble() * 0.4,
        color: color * (1.5 + _rnd.nextDouble()),
        size: 0.02,
        drag: 3,
        gravity: -1.5,
        trail: 0.05,
      );
    }
    _spawn(at, b, 0.9);
  }
}
