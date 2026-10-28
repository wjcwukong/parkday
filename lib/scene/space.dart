import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Maps a full-screen overlay scene onto Flutter's logical pixels.
///
/// The camera looks down +Z at the z = 0 plane from a distance chosen so
/// that one world unit on that plane covers [ppu] logical pixels, with the
/// origin at the center of the view. A 3D character can then sit exactly on
/// top of a widget, while things in front of or behind the plane still get a
/// gentle perspective.
class ScreenSpace {
  ScreenSpace(this.size, {this.ppu = 100, this.fovDegrees = 28});

  final Size size;
  final double ppu;
  final double fovDegrees;

  double get fov => fovDegrees * vm.degrees2Radians;
  double get distance => (size.height / ppu) / 2 / math.tan(fov / 2);

  late final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: fov,
    position: vm.Vector3(0, 0, -distance),
    target: vm.Vector3.zero(),
    fovNear: 0.5,
    fovFar: distance + 60,
  );

  /// The point on the z = 0 plane under a screen position.
  vm.Vector3 toWorld(Offset p, [double z = 0]) {
    final s = (distance + z) / distance;
    return vm.Vector3((p.dx - size.width / 2) / ppu * s, (size.height / 2 - p.dy) / ppu * s, z);
  }

  /// Where a world point lands on screen.
  Offset toScreen(vm.Vector3 w) {
    final s = distance / (distance + w.z);
    return Offset(size.width / 2 + w.x * ppu * s, size.height / 2 - w.y * ppu * s);
  }

  /// Pixels per world unit at depth [z].
  double scaleAt(double z) => ppu * distance / (distance + z);
}

/// Projects many world points through one camera per frame.
class Projector {
  Projector(Camera camera, this.size) : _m = camera.getViewTransform(size);
  final Size size;
  final vm.Matrix4 _m;

  Offset? call(double x, double y, double z) {
    final m = _m.storage;
    final cx = m[0] * x + m[4] * y + m[8] * z + m[12];
    final cy = m[1] * x + m[5] * y + m[9] * z + m[13];
    final cw = m[3] * x + m[7] * y + m[11] * z + m[15];
    if (cw <= 0.01) return null;
    return Offset((cx / cw + 1) / 2 * size.width, (1 - cy / cw) / 2 * size.height);
  }

  /// Approximate pixels per world unit at the depth of a point.
  double scaleAt(double x, double y, double z, double fovY) {
    final m = _m.storage;
    final cw = m[3] * x + m[7] * y + m[11] * z + m[15];
    if (cw <= 0.01) return 0;
    return size.height / (2 * math.tan(fovY / 2) * cw);
  }
}
