import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The four spirits you can play with.
enum Friend { lumi, juju, mochi, nova }

/// Things Lumi can wear.
enum Hat { none, starSprout, beanie, flowerCrown, headphones, catEars }

/// Facial expressions, blended smoothly by [LumiRig.update].
enum Face { idle, happy, sleepy, asleep, surprised, munch, dizzy, wink, talk, starry }

class FriendStyle {
  const FriendStyle({
    required this.name,
    required this.tagline,
    required this.tint,
    required this.rim,
    required this.orb,
    this.headRadius = 0.56,
    this.bodyRadius = 0.31,
    this.swirl = 1.0,
  });
  final String name;
  final String tagline;
  final vm.Vector3 tint;
  final vm.Vector3 rim;
  final vm.Vector3 orb;
  final double headRadius;
  final double bodyRadius;
  final double swirl;

  static final styles = {
    Friend.lumi: FriendStyle(
      name: 'Lumi',
      tagline: 'LANTERN SPIRIT',
      tint: vm.Vector3(0.13, 0.38, 1.0),
      rim: vm.Vector3(0.45, 0.75, 1.0),
      orb: vm.Vector3(2.0, 0.45, 0.1),
    ),
    Friend.juju: FriendStyle(
      name: 'Juju',
      tagline: 'GUMMY TOY',
      tint: vm.Vector3(1.0, 0.16, 0.14),
      rim: vm.Vector3(1.0, 0.6, 0.52),
      orb: vm.Vector3(0.15, 1.6, 1.3),
      headRadius: 0.48,
      bodyRadius: 0.36,
    ),
    Friend.mochi: FriendStyle(
      name: 'Mochi',
      tagline: 'SOFT PEBBLE',
      tint: vm.Vector3(1.0, 0.62, 0.3),
      rim: vm.Vector3(1.0, 0.92, 0.7),
      orb: vm.Vector3(0.5, 1.6, 0.4),
      headRadius: 0.58,
      bodyRadius: 0.28,
      swirl: 0.35,
    ),
    Friend.nova: FriendStyle(
      name: 'Nova',
      tagline: 'ORBIT GUIDE',
      tint: vm.Vector3(0.12, 0.06, 0.7),
      rim: vm.Vector3(0.7, 0.45, 1.0),
      orb: vm.Vector3(1.0, 0.8, 2.2),
    ),
  };
}

/// Shared geometry so that every rig (home, room, games) reuses buffers.
/// The drawn eye shapes, unit sized in the XY plane (facing -Z).
enum EyeShape { oval, arcUp, arcDown, star, swirl }

class _EyeShapes {
  _EyeShapes(Material mat) {
    for (final shape in [EyeShape.arcUp, EyeShape.arcDown, EyeShape.star, EyeShape.swirl]) {
      final geo = switch (shape) {
        EyeShape.arcUp => _Geo.arcUp,
        EyeShape.arcDown => _Geo.arcDown,
        EyeShape.star => _Geo.star,
        _ => _Geo.swirl,
      };
      final n = Node(mesh: Mesh(geo, mat))..visible = false;
      _nodes[shape] = n;
      node.add(n);
    }
  }

  final Node node = Node(name: 'eye shapes');
  final Map<EyeShape, Node> _nodes = {};

  void show(EyeShape shape, vm.Vector3 at, double size, double time, double side) {
    _nodes.forEach((k, n) => n.visible = k == shape);
    node.position = at;
    node.scale = vm.Vector3.all(size);
    node.rotation = switch (shape) {
      EyeShape.swirl => vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), time * 7 * side),
      EyeShape.star => vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.sin(time * 3) * 0.2),
      _ => vm.Quaternion.identity(),
    };
  }
}

class _Geo {
  static final sphereHi = SphereGeometry(radius: 1, segments: 48, rings: 24);
  static final sphere = SphereGeometry(radius: 1, segments: 24, rings: 12);
  static final sphereLo = SphereGeometry(radius: 1, segments: 10, rings: 6);

  // Expression strokes, unit sized and flat on the XY plane.
  static final arcUp = _stroke([for (var i = 0; i <= 8; i++) _arcPoint(math.pi * i / 8, 0.42, 0.34, -0.12)]);
  static final arcDown = _stroke([
    for (var i = 0; i <= 8; i++) _arcPoint(math.pi + math.pi * i / 8, 0.42, 0.2, 0.08),
  ]);
  static final smile = _stroke([
    for (var i = 0; i <= 8; i++) _arcPoint(math.pi * 1.12 + math.pi * 0.76 * i / 8, 0.5, 0.42, 0.2),
  ], 0.1);
  static final star = _starGeometry(0.62, 0.28, 0.1);
  static final swirl = _stroke([
    for (var i = 0; i <= 28; i++)
      vm.Vector3(
        math.cos(i / 28 * math.pi * 3.5) * (0.06 + 0.42 * i / 28),
        math.sin(i / 28 * math.pi * 3.5) * (0.06 + 0.42 * i / 28),
        0,
      ),
  ], 0.075);

  static vm.Vector3 _arcPoint(double a, double rx, double ry, double dy) =>
      vm.Vector3(math.cos(a) * rx, math.sin(a) * ry + dy, 0);

  static Geometry _stroke(List<vm.Vector3> pts, [double radius = 0.11]) =>
      TubeGeometry(CatmullRomPath(pts), radius: radius, radialSegments: 8, stations: pts.length * 4);
}

UnlitMaterial unlit(double r, double g, double b, [double a = 1]) {
  final m = UnlitMaterial()..baseColorFactor = vm.Vector4(r, g, b, a);
  if (a < 1) m.alphaMode = AlphaMode.blend;
  return m;
}

Node ball(Material m, double radius, {vm.Vector3? at, vm.Vector3? scale, Geometry? geo}) {
  final n = Node(mesh: Mesh(geo ?? _Geo.sphere, m));
  n.scale = scale ?? vm.Vector3.all(radius);
  if (at != null) n.position = at;
  return n;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// A linear scene color as a Flutter (sRGB) color, normalized so that HDR
/// values keep their hue.
Color displayColor(vm.Vector3 c, {bool normalize = false}) {
  var r = c.x, g = c.y, b = c.z;
  if (normalize) {
    final m = math.max(r, math.max(g, b));
    if (m > 0) {
      r /= m;
      g /= m;
      b /= m;
    }
  }
  int ch(double v) => (math.pow(v.clamp(0.0, 1.0), 1 / 2.2) * 255).round();
  return Color.fromARGB(255, ch(r), ch(g), ch(b));
}

/// Lumi: a glass lantern spirit built from primitives.
///
/// The hierarchy is
///   root (placement) > squash (squash & stretch) > head pivot (gaze) > face,
/// with the body and the glowing orbs hanging under the squash node. All
/// animation is driven from [update], which eases toward the target values
/// the behaviour code sets each frame.
class LumiRig {
  LumiRig._(this.headMat, this.bodyMat);

  static Future<LumiRig> create() async {
    final head = await loadFmatMaterial('assets/materials/lumi_glass.fmat');
    final body = await loadFmatMaterial('assets/materials/lumi_glass.fmat');
    return LumiRig._(head, body).._build();
  }

  final PreprocessedMaterial headMat;
  final PreprocessedMaterial bodyMat;
  final orbMat = unlit(2.0, 0.45, 0.1);
  final eyeMat = unlit(5.0, 5.4, 6.0);
  final mouthMat = unlit(4.0, 4.4, 5.0);

  final Node root = Node(name: 'lumi');
  final Node squash = Node(name: 'squash');
  final Node headPivot = Node(name: 'head');
  late final Node head, body, handL, handR, foot, eyeL, eyeR, mouth, hatSlot;
  late final _EyeShapes _shapesL, _shapesR;
  late final Node smile;
  late final Node ring, umbrella, snowman;
  final Map<Hat, Node> hats = {};

  Friend _friend = Friend.lumi;
  FriendStyle get style => FriendStyle.styles[_friend]!;
  Friend get friend => _friend;

  // ---- animation targets (set by behaviour code) ----
  Face face = Face.idle;
  vm.Vector2 gaze = vm.Vector2.zero(); // -1..1 look direction
  double glow = 1.0;
  double blush = 0.0;
  double squashY = 1.0; // target vertical stretch (1 = rest)
  double tilt = 0.0; // head roll in radians
  double spin = 0.0; // body yaw in radians
  double handsUp = 0.0; // 0 rest, 1 raised (cheering / holding)
  bool showUmbrella = false;
  bool showSnowman = false;

  /// Whether the face is drawn. The glass doesn't hide what is behind it,
  /// so a camera behind Lumi would see the face through its head.
  bool faceShown = true;

  /// Where the head was last poked, in head space (unit vector, -Z faces
  /// the camera). [pokeHead] presses it in; it springs back on its own.
  final vm.Vector3 _pokeDir = vm.Vector3(0, 0, -1);
  double _pokeTarget = 0, _poke = 0, _pokeVel = 0;
  double _jiggle = 0;

  /// Dents the head toward [dir] (head space) and sets it wobbling.
  void pokeHead(vm.Vector3 dir, {double depth = 1}) {
    _pokeDir.setFrom(dir.normalized());
    _pokeTarget = depth;
    _jiggle = math.max(_jiggle, 0.6 * depth);
  }

  /// Releases a held poke so the dent springs back.
  void releasePoke() => _pokeTarget = 0;

  /// Adds a little wobble without a dent (petting, landing, swaps).
  void wobble([double amount = 0.35]) => _jiggle = math.max(_jiggle, amount);

  // ---- smoothed state ----
  double _glow = 1, _blush = 0, _sq = 1, _tilt = 0, _spin = 0, _hands = 0;
  final vm.Vector2 _gaze = vm.Vector2.zero();
  final vm.Vector2 _eye = vm.Vector2(1, 1);
  final vm.Vector2 _eyeR = vm.Vector2(1, 1);
  final vm.Vector2 _mouth = vm.Vector2(1, 1);
  double _eyeLift = 0;
  double _blinkT = 2.5;
  double _blink = 0;
  double _umbrella = 0;
  double _snow = 0;
  double _time = 0;

  void _build() {
    root.add(squash);
    squash.add(headPivot);
    head = ball(headMat, 1, geo: _Geo.sphereHi);
    headPivot.add(head);
    eyeL = ball(eyeMat, 1);
    eyeR = ball(eyeMat, 1);
    mouth = ball(mouthMat, 1);
    _shapesL = _EyeShapes(eyeMat);
    _shapesR = _EyeShapes(eyeMat);
    smile = Node(mesh: Mesh(_Geo.smile, mouthMat));
    headPivot
      ..add(eyeL)
      ..add(eyeR)
      ..add(mouth)
      ..add(_shapesL.node)
      ..add(_shapesR.node)
      ..add(smile);
    hatSlot = Node(name: 'hat');
    headPivot.add(hatSlot);

    body = ball(bodyMat, 1, geo: _Geo.sphereHi);
    squash.add(body);
    handL = ball(orbMat, 0.085);
    handR = ball(orbMat, 0.085);
    foot = ball(orbMat, 0.095);
    squash
      ..add(handL)
      ..add(handR)
      ..add(foot);

    ring = Node(mesh: Mesh(TorusGeometry(radius: 0.86, tubeRadius: 0.025), unlit(1.6, 1.3, 3.2)));
    ring.visible = false;
    headPivot.add(ring);

    _buildHats();
    umbrella = _buildUmbrella();
    umbrella.visible = false;
    squash.add(umbrella);
    snowman = _buildSnowman();
    snowman.visible = false;
    root.add(snowman);

    setFriend(Friend.lumi);
    update(0);
  }

  void setFriend(Friend f) {
    _friend = f;
    final s = style;
    for (final m in [headMat, bodyMat]) {
      m.parameters
        ..setVec4('tint', vm.Vector4(s.tint.x, s.tint.y, s.tint.z, 1))
        ..setVec3('rim_color', s.rim)
        ..setFloat('swirl', s.swirl);
    }
    _setOrb(s.orb);
    ring.visible = f == Friend.nova;
    head.scale = vm.Vector3.all(s.headRadius);
    body.scale = vm.Vector3.all(s.bodyRadius);
    body.position = vm.Vector3(0, -(s.headRadius + s.bodyRadius * 0.62), 0);
    hatSlot.position = vm.Vector3(0, s.headRadius * 0.82, 0);
    hatSlot.scale = vm.Vector3.all(s.headRadius / 0.56);
  }

  /// Overrides the body tint (wardrobe "Colors").
  void setTint(vm.Vector3? tint) {
    final t = tint ?? style.tint;
    for (final m in [headMat, bodyMat]) {
      m.parameters.setVec4('tint', vm.Vector4(t.x, t.y, t.z, 1));
    }
  }

  /// Overrides the orb color (wardrobe "Glow").
  void setOrbColor(vm.Vector3? c) {
    _setOrb(c ?? style.orb);
  }

  // The orbs render well above 1.0 so bloom gives them their halo; the
  // light they cast into the jelly uses the plain color.
  final vm.Vector3 _orbColor = vm.Vector3(2.0, 0.45, 0.1);
  static const double _orbBoost = 2.0;

  void _setOrb(vm.Vector3 o) {
    _orbColor.setFrom(o);
    orbMat.baseColorFactor = vm.Vector4(o.x * _orbBoost, o.y * _orbBoost, o.z * _orbBoost, 1);
  }

  Hat _hat = Hat.none;
  Hat get hat => _hat;
  set hat(Hat h) {
    _hat = h;
    hats.forEach((k, n) => n.visible = k == h);
  }

  void _buildHats() {
    for (final h in Hat.values) {
      if (h == Hat.none) continue;
      final n = buildHat(h)..visible = false;
      hats[h] = n;
      hatSlot.add(n);
    }
  }

  Node _buildUmbrella() {
    final u = Node(name: 'umbrella');
    final canopy = Node(
      mesh: Mesh(
        CylinderGeometry(bottomRadius: 0.62, topRadius: 0.03, height: 0.24, bottomCap: false),
        unlit(1.2, 0.42, 0.52)..doubleSided = true,
      ),
    );
    canopy.position = vm.Vector3(0, 1.05, 0);
    u.add(canopy);
    u.add(
      Node(
        mesh: Mesh(
          CylinderGeometry(bottomRadius: 0.015, topRadius: 0.015, height: 1.1),
          unlit(1.4, 1.2, 1.1),
        ),
      )..position = vm.Vector3(0, 0.5, 0),
    );
    u.add(ball(orbMat, 0.05, at: vm.Vector3(0, -0.05, 0)));
    return u;
  }

  Node _buildSnowman() {
    final s = Node(name: 'snowman');
    final snow = unlit(2.4, 2.5, 2.7);
    s.add(ball(snow, 0.16, at: vm.Vector3(0, 0, 0)));
    s.add(ball(snow, 0.11, at: vm.Vector3(0, 0.22, 0)));
    s.add(ball(unlit(0.1, 0.1, 0.2), 0.016, at: vm.Vector3(-0.04, 0.25, -0.1)));
    s.add(ball(unlit(0.1, 0.1, 0.2), 0.016, at: vm.Vector3(0.04, 0.25, -0.1)));
    s.add(
      Node(mesh: Mesh(CylinderGeometry(bottomRadius: 0.02, topRadius: 0.0, height: 0.08), unlit(3, 1.2, 0.2)))
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -math.pi / 2)
        ..position = vm.Vector3(0, 0.21, -0.13),
    );
    return s;
  }

  /// Advances blink, expression blending and secondary motion.
  void update(double dt) {
    _time += dt;
    final k = 1 - math.exp(-dt * 10);
    final kSlow = 1 - math.exp(-dt * 4);
    final s = style;

    _glow = _lerp(_glow, glow, kSlow);
    _blush = _lerp(_blush, blush, kSlow);
    _sq = _lerp(_sq, squashY, 1 - math.exp(-dt * 14));
    _tilt = _lerp(_tilt, tilt, k);
    _spin = _lerp(_spin, spin, kSlow);
    _hands = _lerp(_hands, handsUp, k);
    _gaze.x = _lerp(_gaze.x, gaze.x.clamp(-1, 1), kSlow);
    _gaze.y = _lerp(_gaze.y, gaze.y.clamp(-1, 1), kSlow);
    _umbrella = _lerp(_umbrella, showUmbrella ? 1 : 0, kSlow);
    _snow = _lerp(_snow, showSnowman ? 1 : 0, kSlow);

    // The dent follows a springy target so a released poke overshoots and
    // settles, and the jiggle fades out.
    for (var left = dt; left > 0; left -= 1 / 240) {
      final h = math.min(left, 1 / 240);
      _pokeVel += ((_pokeTarget - _poke) * 220 - _pokeVel * 14) * h;
      _poke = (_poke + _pokeVel * h).clamp(-0.35, 1.0);
    }
    _jiggle = math.max(0, _jiggle - dt * 0.9);

    for (final m in [headMat, bodyMat]) {
      m.parameters
        ..setFloat('glow', _glow)
        ..setFloat('blush', m == headMat ? _blush : 0)
        ..setFloat('time', _time)
        ..setFloat('jiggle', _jiggle);
    }
    headMat.parameters.setVec4('poke', vm.Vector4(_pokeDir.x, _pokeDir.y, _pokeDir.z, _poke));
    bodyMat.parameters.setVec4('poke', vm.Vector4(0, 0, -1, 0));

    // Squash & stretch preserves volume.
    final sx = 1 / math.sqrt(_sq);
    squash.scale = vm.Vector3(sx, _sq, sx);
    squash.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _spin);
    headPivot.rotation = vm.Quaternion.euler(_gaze.x * 0.45, -_gaze.y * 0.3, _tilt);

    // Blinking (not while the eyes are already closed).
    _blinkT -= dt;
    if (_blinkT <= 0) {
      _blink = 1;
      _blinkT = 2.2 + math.Random().nextDouble() * 3;
    }
    _blink = math.max(0, _blink - dt * 7);
    final blinkMul = 1 - math.sin(_blink * math.pi) * 0.9;

    // Expression table: eye width/height, eye lift, mouth width/height.
    double ew = 1, eh = 1, lift = 0, mw = 1, mh = 1, rw = 1, rh = 1;
    switch (face) {
      case Face.idle:
        mw = 1.2;
        mh = 0.9;
      case Face.happy:
        eh = 0.32;
        lift = 0.03;
        mw = 1.3;
        mh = 1.4;
      case Face.sleepy:
        eh = 0.38;
        lift = -0.02;
        mw = 0.6;
        mh = 0.5;
      case Face.asleep:
        eh = 0.12;
        lift = -0.03;
        mw = 0.5;
        mh = 0.7 + 0.25 * math.sin(_time * 1.6);
      case Face.surprised:
        ew = 1.15;
        eh = 1.2;
        mw = 0.7;
        mh = 2.2;
      case Face.munch:
        eh = 0.35;
        lift = 0.02;
        mw = 1.2;
        mh = 0.5 + 1.6 * (0.5 + 0.5 * math.sin(_time * 22));
      case Face.dizzy:
        ew = 1.1 + 0.15 * math.sin(_time * 18);
        eh = 1.1 + 0.15 * math.cos(_time * 18);
        mw = 0.8;
        mh = 1.1;
      case Face.wink:
        rh = 0.12;
        rw = 1.1;
        mw = 1.2;
        mh = 1.1;
      case Face.talk:
        mw = 1.0;
        mh = 0.6 + 1.3 * (0.5 + 0.5 * math.sin(_time * 16) * math.sin(_time * 5.3));
      case Face.starry:
        mw = 1.4;
        mh = 1.4;
    }
    final closed = face == Face.asleep;
    final bm = closed ? 1.0 : blinkMul;
    _eye.x = _lerp(_eye.x, ew, k);
    _eye.y = _lerp(_eye.y, eh * bm, 1 - math.exp(-dt * 25));
    _eyeR.x = _lerp(_eyeR.x, ew * rw, k);
    _eyeR.y = _lerp(_eyeR.y, eh * (face == Face.wink ? rh : 1) * bm, 1 - math.exp(-dt * 25));
    _eyeLift = _lerp(_eyeLift, lift, k);
    _mouth.x = _lerp(_mouth.x, mw, k);
    _mouth.y = _lerp(_mouth.y, mh, 1 - math.exp(-dt * 20));

    final r = s.headRadius;
    // Features sit just under the jelly's surface so it veils them.
    vm.Vector3 onHead(double x, double y, [double inset = 0.045]) {
      final z = -math.sqrt(math.max(0.0, r * r - x * x - y * y)) + inset;
      return vm.Vector3(x, y, z);
    }

    final ex = r * 0.29, ey = r * 0.04 + _eyeLift;
    eyeL.position = onHead(-ex, ey);
    eyeR.position = onHead(ex, ey);
    eyeL.scale = vm.Vector3(0.085 * _eye.x, 0.118 * _eye.y, 0.035);
    eyeR.scale = vm.Vector3(0.085 * _eyeR.x, 0.118 * _eyeR.y, 0.035);
    mouth.position = onHead(0, -r * 0.27, 0.04);
    mouth.scale = vm.Vector3(0.05 * _mouth.x, 0.02 * _mouth.y, 0.03);

    // Drawn shapes take over from the ovals for some expressions: closed
    // happy arcs, sleeping lids, spinning dizzy swirls and star eyes.
    final (shapeL, shapeR) = switch (face) {
      Face.happy => (EyeShape.arcUp, EyeShape.arcUp),
      Face.asleep => (EyeShape.arcDown, EyeShape.arcDown),
      Face.wink => (EyeShape.oval, EyeShape.arcUp),
      Face.dizzy => (EyeShape.swirl, EyeShape.swirl),
      Face.starry => (EyeShape.star, EyeShape.star),
      _ => (EyeShape.oval, EyeShape.oval),
    };
    final eyeSize = 0.17 * (r / 0.56);
    _shapesL.show(shapeL, eyeL.position, eyeSize, _time, 1);
    _shapesR.show(shapeR, eyeR.position, eyeSize, _time, -1);
    eyeL.visible = faceShown && shapeL == EyeShape.oval;
    eyeR.visible = faceShown && shapeR == EyeShape.oval;
    _shapesL.node.visible = faceShown;
    _shapesR.node.visible = faceShown;

    // A drawn smile unless the mouth is open.
    final open = switch (face) {
      Face.surprised || Face.munch || Face.talk || Face.dizzy => true,
      _ => false,
    };
    mouth.visible = faceShown && open;
    smile.visible = faceShown && !open;
    smile.position = onHead(0, -r * 0.24, 0.04);
    final sw = 0.13 * (r / 0.56) * (0.7 + 0.3 * _mouth.x);
    smile.scale = vm.Vector3(sw, sw * (0.55 + 0.25 * _mouth.y), sw);

    // Hands hang by the body and lift when cheering; they bob out of phase.
    final hb = math.sin(_time * 2.1) * 0.03;
    final hy = -r - 0.05 + _hands * 0.55;
    final hx = r + 0.08 - _hands * 0.08;
    handL.position = vm.Vector3(-hx, hy + hb, -0.05);
    handR.position = vm.Vector3(hx, hy - hb, -0.05);
    foot.position = vm.Vector3(0, body.position.y - s.bodyRadius - 0.13 + math.sin(_time * 2.6) * 0.02, 0);

    umbrella.visible = _umbrella > 0.02;
    umbrella.scale = vm.Vector3.all(_umbrella.clamp(0.001, 1));
    umbrella.position = vm.Vector3(hx * 0.95, hy + 0.05, -0.08);
    umbrella.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -0.32);

    snowman.visible = _snow > 0.02;
    snowman.scale = vm.Vector3.all(_snow.clamp(0.001, 1) * 1.3);
    snowman.position = vm.Vector3(1.35, -1.0 + math.sin(_time * 1.3) * 0.04, 0.2);

    // The orbs light the jelly from inside.
    final oc = _orbColor;
    vm.Vector4 lamp(Node n) {
      final p = n.globalTransform.getTranslation();
      return vm.Vector4(p.x, p.y, p.z, 1);
    }

    final la = lamp(handL), lb = lamp(handR), lc = lamp(foot);
    for (final m in [headMat, bodyMat]) {
      m.parameters
        ..setVec3('orb_color', vm.Vector3(oc.x, oc.y, oc.z))
        ..setVec4('orb_a', la)
        ..setVec4('orb_b', lb)
        ..setVec4('orb_c', lc);
    }

    if (ring.visible) {
      ring.rotation = vm.Quaternion.euler(0, 1.2, math.sin(_time * 0.7) * 0.25);
    }
  }
}

/// Builds a wearable hat, sized for a head of radius 0.56.
Node buildHat(Hat hat) {
  switch (hat) {
    case Hat.none:
      return Node();
    case Hat.starSprout:
      // Star sprout: a little stem with a glowing star on top.
      final sprout = Node();
      sprout.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(bottomRadius: 0.018, topRadius: 0.012, height: 0.26),
            unlit(0.5, 1.4, 0.7),
          ),
        )..position = vm.Vector3(0, 0.1, 0),
      );
      sprout.add(
        Node(mesh: Mesh(_starGeometry(0.11, 0.05, 0.035), unlit(4, 3.4, 1.2)))
          ..position = vm.Vector3(0, 0.27, 0),
      );
      sprout.add(
        ball(unlit(0.6, 1.6, 0.8), 1, at: vm.Vector3(0.05, 0.12, 0), scale: vm.Vector3(0.06, 0.025, 0.035)),
      );
      return sprout;
    case Hat.beanie:
      // Beanie: a pink knit dome with a cream cuff and a pompom.
      final beanie = Node();
      final pink = unlit(1.0, 0.45, 0.58);
      beanie.add(
        ball(pink, 1, at: vm.Vector3(0, -0.08, 0), scale: vm.Vector3(0.5, 0.33, 0.5), geo: _Geo.sphereHi),
      );
      beanie.add(
        Node(
          mesh: Mesh(
            TorusGeometry(radius: 0.46, tubeRadius: 0.07, radialSegments: 40),
            unlit(1.0, 0.92, 0.85),
          ),
        )..position = vm.Vector3(0, -0.12, 0),
      );
      beanie.add(ball(unlit(1.0, 0.9, 0.92), 0.1, at: vm.Vector3(0, 0.26, 0)));
      return beanie;
    case Hat.flowerCrown:
      // Flower crown: a vine ring dotted with blossoms.
      final crown = Node();
      crown.add(
        Node(
          mesh: Mesh(
            TorusGeometry(radius: 0.36, tubeRadius: 0.022, radialSegments: 40),
            unlit(0.35, 0.9, 0.45),
          ),
        )..position = vm.Vector3(0, 0.02, 0),
      );
      const petals = [
        [1.6, 0.7, 0.9],
        [1.8, 1.5, 0.6],
        [1.2, 1.2, 1.9],
        [1.9, 1.0, 1.4],
      ];
      for (var i = 0; i < 10; i++) {
        final a = i / 10 * math.pi * 2;
        final c = petals[i % petals.length];
        crown.add(
          ball(unlit(c[0], c[1], c[2]), 0.055, at: vm.Vector3(math.cos(a) * 0.36, 0.04, math.sin(a) * 0.36)),
        );
      }
      return crown;
    case Hat.headphones:
      // Headphones: a band over the top and two cups.
      final phones = Node();
      final band = Node(
        mesh: Mesh(TorusGeometry(radius: 0.6, tubeRadius: 0.035, radialSegments: 48), unlit(0.9, 0.95, 1.1)),
      );
      band.rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2);
      band.position = vm.Vector3(0, -0.42, 0);
      phones.add(band);
      for (final s in [-1.0, 1.0]) {
        final cup = Node(
          mesh: Mesh(
            CylinderGeometry(bottomRadius: 0.16, topRadius: 0.16, height: 0.12),
            unlit(0.85, 0.9, 1.05),
          ),
        );
        cup.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi / 2);
        cup.position = vm.Vector3(s * 0.58, -0.45, 0);
        phones.add(cup);
        phones.add(ball(unlit(1.2, 1.6, 3.0), 0.09, at: vm.Vector3(s * 0.65, -0.45, 0)));
      }
      return phones;
    case Hat.catEars:
      // Cat ears: two soft cones.
      final ears = Node();
      for (final s in [-1.0, 1.0]) {
        final ear = Node(
          mesh: Mesh(
            CylinderGeometry(bottomRadius: 0.13, topRadius: 0.01, height: 0.26),
            unlit(0.9, 0.55, 1.6),
          ),
        );
        ear.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -s * 0.45);
        ear.position = vm.Vector3(s * 0.3, -0.02, 0);
        ears.add(ear);
      }
      return ears;
  }
}

/// A flat five-pointed star, extruded slightly along Z.
Geometry _starGeometry(double outer, double inner, double depth) {
  final pts = <vm.Vector2>[];
  for (var i = 0; i < 10; i++) {
    final a = math.pi / 2 + i * math.pi / 5;
    final rr = i.isEven ? outer : inner;
    pts.add(vm.Vector2(math.cos(a) * rr, math.sin(a) * rr));
  }
  final positions = <double>[];
  final indices = <int>[];
  // Front and back faces as a triangle fan, plus side quads.
  for (final z in [-depth / 2, depth / 2]) {
    positions.addAll([0, 0, z]);
    for (final p in pts) {
      positions.addAll([p.x, p.y, z]);
    }
  }
  final back = pts.length + 1;
  for (var i = 0; i < pts.length; i++) {
    final a = 1 + i, b = 1 + (i + 1) % pts.length;
    indices.addAll([0, b, a]);
    indices.addAll([back, back + a, back + b]);
    indices.addAll([a, b, back + b, a, back + b, back + a]);
  }
  return MeshGeometry.fromArrays(positions: Float32List.fromList(positions), indices: indices);
}

/// Ambient floating sparks, drawn as one instanced batch.
class Sparks {
  Sparks(this.count, {required this.area, double size = 0.035, vm.Vector3? color}) {
    final rnd = math.Random(7);
    mesh = InstancedMesh(geometry: _Geo.sphereLo, material: unlit(1, 1, 1), sortTransparentInstances: false);
    final c = color ?? vm.Vector3(1.5, 0.42, 0.1);
    for (var i = 0; i < count; i++) {
      final p = vm.Vector3(
        area.min.x + rnd.nextDouble() * (area.max.x - area.min.x),
        area.min.y + rnd.nextDouble() * (area.max.y - area.min.y),
        area.min.z + rnd.nextDouble() * (area.max.z - area.min.z),
      );
      _pos.add(p);
      _phase.add(rnd.nextDouble() * 6.28);
      _size.add(size * (0.4 + rnd.nextDouble()));
      final b = 0.5 + rnd.nextDouble() * 0.8;
      mesh.addInstance(_m(p, _size[i]), color: vm.Vector4(c.x * b, c.y * b, c.z * b, 1));
    }
    node.addComponent(InstancedMeshComponent(mesh));
  }

  final int count;
  vm.Aabb3 area;
  late final InstancedMesh mesh;
  final Node node = Node(name: 'sparks');
  final _pos = <vm.Vector3>[];
  final _phase = <double>[];
  final _size = <double>[];
  double _t = 0;
  double speed = 1;

  static vm.Matrix4 _m(vm.Vector3 p, double s) =>
      vm.Matrix4.translation(p)..scaleByVector3(vm.Vector3.all(s));

  void update(double dt) {
    _t += dt;
    final h = area.max.y - area.min.y;
    mesh.updateInstanceTransforms((list) {
      for (var i = 0; i < count; i++) {
        final p = _pos[i];
        p.y += dt * 0.12 * speed;
        if (p.y > area.max.y) p.y -= h;
        final wob = math.sin(_t * 0.8 + _phase[i]) * 0.12;
        final tw = 0.75 + 0.25 * math.sin(_t * 3 + _phase[i] * 2);
        list[i]
          ..setIdentity()
          ..translateByVector3(vm.Vector3(p.x + wob, p.y, p.z))
          ..scaleByVector3(vm.Vector3.all(_size[i] * tw));
      }
    }, recomputeWinding: false);
  }
}
