import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/fx.dart';
import '../scene/lumi_rig.dart';
import '../scene/note_card.dart';
import '../scene/space.dart';

enum Weather { clear, rain, snow }

/// A park notification that slides in and gets eaten.
class ParkNote {
  ParkNote(this.kind, this.title, this.body, this.after, this.icon);
  final String kind; // "Treats", "Reward", ...
  final String title;
  final String body;
  final String after; // status line once Lumi has eaten it
  final IconData icon;

  // Animation state, owned by the brain.
  double age = 0;
  Offset pos = Offset.zero; // where the card shows on screen
  NoteCard? card;
  double opacity = 0;

  /// How much the card is drawn as the solid card in front of Lumi (1)
  /// rather than the glowing one inside the glass head (0).
  double front = 1;
  bool _loading = false;
  bool eaten = false;
  bool done = false;
}

/// Everything Lumi does on the home screen.
///
/// The brain owns the overlay [scene], decides what Lumi should be doing
/// from user input and timers, and writes the result into the [LumiRig]
/// every frame. Widgets read [status], [speech], [notes] and friends.
class LumiBrain extends ChangeNotifier {
  LumiBrain();

  final Scene scene = Scene();
  LumiRig? rig;
  Sparks? sparks;
  HomeFx? fx;
  ScreenSpace? space;
  bool get ready => rig != null;

  /// Bumped every frame so painters can repaint without rebuilding widgets.
  final ValueNotifier<int> frame = ValueNotifier(0);

  // ---------------- layout input ----------------
  /// Where Lumi's head rests, in screen pixels (set by the header layout).
  Offset home = const Offset(195, 140);
  Rect headerRect = Rect.zero;
  Rect scrollRect = Rect.zero;

  // ---------------- public state ----------------
  String defaultStatus = 'Fireworks over the lagoon at 9:15';
  String _status = '';
  double _statusT = 0;
  String get status => _status.isEmpty ? defaultStatus : _status;
  String? speech;
  double _speechT = 0;
  bool listening = false;

  final notes = <ParkNote>[];
  final zzz = <_Zed>[];
  final hearts = <_Heart>[];

  Weather weather = Weather.clear;
  int keys = 4;
  int stars = 103;
  bool asleep = false;
  bool notificationsOn = true;
  bool ambientSparks = true;
  bool riding = false;
  bool away = false;
  Hat hat = Hat.none;
  Friend friend = Friend.lumi;
  int colorIndex = 0;
  int glowIndex = 0;

  // ---------------- internal ----------------
  final _rnd = math.Random();
  double _t = 0;
  Offset _pos = const Offset(195, 140);
  Offset _vel = Offset.zero;
  double _scale = 1, _scaleTarget = 1;
  double _petCharge = 0;
  bool _petting = false;
  double _petIdle = 0;
  double _dizzyT = 0, _eatT = 0, _trickT = 0, _surpriseT = 0, _emoteT = 0;
  double _cheerT = 0;
  double _starryT = 0;
  double _holdT = 0;
  Face _emote = Face.wink;
  double _noteTimer = 4;
  double _scrollIdle = 99, _scrollActive = 0;
  double _scrollFrac = 0;
  double _awayT = 0;
  double _swapT = 0;
  Friend? _pendingFriend;
  Offset? _pointer;
  Offset? _lastPet;
  int _lastPetMs = 0;
  double _roughness = 0;
  int _noteCursor = 0;

  // ---------------- page fly-over ----------------
  /// How far the page is tipped back into 3D, in radians (top away). The
  /// home page applies the same tilt to its widgets with a perspective
  /// matching [camera], so the UI and the scene stay in register.
  double pageTilt = 0;

  /// The page's turn about its vertical axis, and how far it is lifted up
  /// the screen and pulled towards the viewer (logical pixels) while
  /// tilted. Fitted to the original's frames: about 47 degrees, with the
  /// page brought up and in so the header stays near the top.
  double pageYaw = 0, pageLift = 0, pagePush = 0;
  double _flyT = -1;
  bool get flying => _flyT >= 0;

  /// The cards Lumi can hop between while the page is tipped back: each
  /// one's rect on the flat page, how high it then stands off the page and
  /// how far it moves down it (logical pixels), by index; null for cards
  /// that are off screen or stay down. Set by the home page.
  List<(Rect, double, double)?> Function()? hopCards;

  /// How high the header stands off the tipped-back page, logical pixels.
  static const headerLift = 70.0;

  /// How far each card is pressed in by Lumi landing on it, by index,
  /// springing back to 0.
  final cardPress = <int, double>{};

  // The hops: where Lumi's feet land on the page and on which card (-1 is
  // the header, where it floats), the hop under way and the time into it,
  // and when the page starts to tip back.
  final _stops = <(Offset, int, double, double)>[];
  int _leg = 0;
  double _legT = 0, _flyEnd = double.infinity;
  Offset _feet = Offset.zero; // on the page
  bool _landed = false;
  double _hopLift = 0, _hopLean = 0;
  double _hopUp = 0; // how high Lumi is in its hop, in world units up the screen
  double _feetZ = 0; // off the page, in world units (-Z)
  static const _crouch = 0.16, _land = 0.2, _dwell = 0.3;

  /// How far into the fly-over tilt the page is, 0 (flat) to 1.
  double get tiltAmount => (pageTilt / _tiltMax).clamp(0, 1);
  static const _tiltMax = 0.82;

  /// Tips the page back into a few layers and lets Lumi hop between them
  /// card by card, each one dipping and lighting up as it lands, then hop
  /// back up to the header and set everything back.
  void flyover() {
    if (flying || asleep || away || space == null || notes.isNotEmpty) return;
    final cards = <(Rect, int, double, double)>[];
    final all = hopCards?.call() ?? const [];
    for (var i = 0; i < all.length; i++) {
      final c = all[i];
      if (c != null) cards.add((c.$1, i, c.$2, c.$3));
    }
    // Down the layers and back up one before the header, zigzagging.
    final order = [...cards, if (cards.length > 2) cards.first];
    _stops.clear();
    var side = 0.3;
    for (final (r, i, lift, spread) in order) {
      _stops.add((Offset(r.left + r.width * (side + _rnd.nextDouble() * 0.08), r.center.dy + 6), i, lift, spread));
      side = 1 - side - 0.08;
    }
    _stops.add((Offset.zero, -1, headerLift, 0));
    _leg = 0;
    _legT = 0;
    _flyEnd = double.infinity;
    _flyT = 0;
    _setStatus('Lumi is exploring the page', 999);
    notifyListeners();
  }

  /// The tilt, turn and lift as a transform of the page's widgets about
  /// their center, with the scene camera's perspective, for a `Transform`
  /// widget.
  Matrix4 get pageMatrix {
    final sp = space;
    if (pageTilt == 0 || sp == null) return Matrix4.identity();
    return Matrix4.identity()
      ..setEntry(3, 2, 1 / (sp.distance * sp.ppu))
      ..translateByDouble(0, -pageLift, -pagePush, 1)
      ..rotateY(pageYaw)
      ..rotateX(-pageTilt);
  }

  /// The overlay camera. Tipping the page is the same as swinging the
  /// camera the other way around it, so the scene stays in register with
  /// [pageMatrix]. (World y is up where the widgets' y is down, which
  /// flips the sign of the tilt and the lift.)
  Camera get camera {
    final sp = space!;
    if (pageTilt == 0) return sp.camera;
    final page =
        vm.Matrix4.translationValues(0, pageLift / sp.ppu, -pagePush / sp.ppu) *
        vm.Matrix4.rotationY(pageYaw) *
        vm.Matrix4.rotationX(pageTilt);
    final inv = vm.Matrix4.inverted(page);
    final dist = sp.distance;
    return PerspectiveCamera(
      fovRadiansY: sp.fov,
      position: inv.transform3(vm.Vector3(0, 0, -dist)),
      target: inv.transform3(vm.Vector3.zero()),
      up: inv.rotated3(vm.Vector3(0, 1, 0)),
      fovNear: 0.5,
      fovFar: dist + 60,
    );
  }

  Offset get lumiPos => _pos;
  double get lumiScale => _scale;
  double get headRadiusPx => (rig?.style.headRadius ?? 0.56) * (space?.ppu ?? 100) * _scale;
  double get petProgress => (_petCharge / 4.5).clamp(0, 1);

  Future<void> init() async {
    await Scene.initializeStaticResources();
    // Lumi is light: an HDR look with bloom, rendered over an opaque black
    // backdrop and screen-blended onto the UI (see LightLayer), so the glow
    // spills past Lumi's silhouette instead of being cut off by alpha.
    scene.environmentSettings = glowSettings();
    scene.add(backdrop());
    // Compile the spark material up front so the first burst is instant.
    await loadFmatMaterial('assets/materials/sparks.fmat');
    fx = HomeFx(scene);
    final r = await LumiRig.create();
    scene.add(r.root);
    final s = Sparks(22, size: 0.022, area: vm.Aabb3.minMax(vm.Vector3(-2.2, 0.6, -0.6), vm.Vector3(2.2, 4.2, 2.5)));
    scene.add(s.node);
    sparks = s;
    rig = r;
    notifyListeners();
  }

  /// The look for a scene of Lumi drawn as light over Flutter widgets: HDR
  /// with bloom. Pair it with [backdrop] and a `LightLayer`.
  static EnvironmentSettings glowSettings() => EnvironmentSettings(
    toneMapping: ToneMappingMode.pbrNeutral,
    exposure: 1.0,
    bloomEnabled: true,
    bloomThreshold: 0.9,
    bloomIntensity: 0.3,
    bloomScatter: 0.62,
  );

  /// A black card far behind Lumi that keeps the scene opaque, so bloom
  /// survives the resolve (it is multiplied by coverage) and screen blending
  /// makes the black disappear.
  static Node backdrop() {
    final mat = UnlitMaterial()
      ..baseColorFactor = vm.Vector4(0, 0, 0, 1)
      ..doubleSided = true;
    return Node(name: 'backdrop', mesh: Mesh(PlaneGeometry(width: 400, depth: 400), mat))
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -math.pi / 2)
      ..position = vm.Vector3(0, 0, 30);
  }

  /// A fresh rig dressed like the home Lumi, for other screens.
  Future<LumiRig> makeRig() async {
    final r = await LumiRig.create();
    r.setFriend(friend);
    r.setTint(tints[colorIndex]);
    r.setOrbColor(glows[glowIndex]);
    r.hat = hat;
    r.showUmbrella = weather == Weather.rain;
    return r;
  }

  void layout(Size size) {
    if (space == null || space!.size != size) {
      space = ScreenSpace(size);
      if (_pos == const Offset(195, 140)) _pos = home;
    }
  }

  // ======================= input =======================

  bool hitsLumi(Offset p) {
    final c = _pos;
    final r = headRadiusPx;
    if ((p - c).distance < r * 1.15) return true;
    // body
    return (p - (c + Offset(0, r * 1.35))).distance < r * 0.7;
  }

  void pointerHover(Offset p) => _pointer = p;
  void pointerExit() => _pointer = null;

  void pointerDown(Offset p, Duration ts) {
    _pointer = p;
    if (!hitsLumi(p) || away) return;
    _petting = true;
    _lastPet = p;
    _lastPetMs = ts.inMilliseconds;
    _downMs = ts.inMilliseconds;
    _roughness = 0;
    _press(p, 0.6);
  }

  /// Dents the jelly under the finger when it is on the head.
  void _press(Offset p, double depth) {
    final r = headRadiusPx;
    if (r < 2) return;
    final d = (p - _pos) / r;
    final dd = d.distanceSquared;
    if (dd > 1.2) return;
    rig?.pokeHead(vm.Vector3(d.dx, -d.dy, -math.sqrt(math.max(0.05, 1 - dd))), depth: depth);
  }

  int _downMs = 0;

  /// Returns true when the move was consumed as petting.
  bool pointerMove(Offset p, Duration ts) {
    _pointer = p;
    if (!_petting) return false;
    final now = ts.inMilliseconds;
    final dtMs = math.max(8, now - _lastPetMs);
    final d = (p - _lastPet!).distance;
    final speed = d / dtMs * 1000; // px/s
    _lastPet = p;
    _lastPetMs = now;
    if (speed > 900 || d > 60) {
      rig?.wobble(0.9);
      _roughness += d / 220;
      if (_roughness > 1.0 && _dizzyT <= 0) _getDizzy();
    } else if (d > 0.5) {
      _petIdle = 0;
      _press(p, 0.35);
      if (asleep) return true;
      if (_petCharge > 0.4 && _rnd.nextDouble() < 0.18) {
        hearts.add(_Heart(p + Offset(_rnd.nextDouble() * 20 - 10, -10)));
      }
    }
    return true;
  }

  void pointerUp(Offset p, Duration ts) {
    if (!_petting) return;
    _petting = false;
    rig?.releasePoke();
    final held = ts.inMilliseconds - _downMs;
    if (_petCharge < 0.15 && held < 400 && _roughness < 0.2) poke();
  }

  void poke() {
    if (asleep) {
      _wake();
      return;
    }
    _vel += const Offset(0, -260);
    rig?.squashY = 0.78;
    Future.delayed(const Duration(milliseconds: 120), () => rig?.squashY = 1.12);
    Future.delayed(const Duration(milliseconds: 260), () => rig?.squashY = 1.0);
    _surpriseT = 0.35;
    _cheerT = 0.6;
    final hi = 'Hi, I’m ${FriendStyle.styles[friend]!.name}!';
    _setStatus(_rnd.nextDouble() < 0.6 ? hi : 'Hehe, that tickles', 3);
  }

  void _getDizzy() {
    _dizzyT = 2.4;
    _petCharge = 0;
    _setStatus('Whoa, slow down', 3);
  }

  void _fallAsleep() {
    asleep = true;
    _petting = false;
    _petCharge = 0;
    _setStatus('Lumi fell asleep. Shh…', 999);
    notifyListeners();
  }

  void _wake() {
    asleep = false;
    _surpriseT = 0.8;
    _vel += const Offset(0, -180);
    _setStatus('*yawn* I’m awake!', 3);
    notifyListeners();
  }

  // scroll from the feed
  void onScroll(double fraction, bool active) {
    _scrollFrac = fraction.clamp(0, 1);
    if (active) {
      _scrollIdle = 0;
    }
  }

  // ======================= actions =======================

  void setFriend(Friend f) {
    if (f == friend && _pendingFriend == null) return;
    _pendingFriend = f;
    _swapT = 0.28;
    _scaleTarget = 0.05;
    final style = FriendStyle.styles[f]!;
    fx?.shockwave(_world(_pos, -0.7), style.rim * 0.6 + style.tint * 0.4);
  }

  /// Lumi's spot in the overlay scene, nudged towards the camera by [z].
  vm.Vector3 _world(Offset p, [double z = 0]) => space?.toWorld(p, z) ?? vm.Vector3.zero();

  /// From the middle of Lumi's head down to the bottom of its body, in
  /// world units at scale 1.
  static double _footLength(LumiRig r) => r.style.headRadius + r.style.bodyRadius * 1.62;

  void setHat(Hat h) {
    hat = h;
    rig?.hat = h;
    _cheerT = 0.8;
    _vel += const Offset(0, -150);
    if (h != Hat.none) _setStatus(_hatLine(h), 3);
    notifyListeners();
  }

  String _hatLine(Hat h) => switch (h) {
    Hat.starSprout => 'A little star sprout!',
    Hat.beanie => 'Cozy beanie on',
    Hat.flowerCrown => 'Flower crown, very fancy',
    Hat.headphones => 'Lumi is vibing',
    Hat.catEars => 'Mew!',
    Hat.none => '',
  };

  // Linear colors (the overlay scene uses linear tone mapping).
  static final tints = <vm.Vector3?>[
    null,
    vm.Vector3(0.25, 0.12, 1.0),
    vm.Vector3(0.05, 0.7, 0.5),
    vm.Vector3(1.0, 0.25, 0.45),
    vm.Vector3(1.0, 0.55, 0.08),
  ];
  static final glows = <vm.Vector3?>[
    null,
    vm.Vector3(0.25, 1.6, 0.9),
    vm.Vector3(1.8, 0.35, 0.8),
    vm.Vector3(1.4, 1.5, 2.0),
  ];

  void setColor(int i) {
    colorIndex = i;
    rig?.setTint(tints[i]);
    notifyListeners();
  }

  void setGlow(int i) {
    glowIndex = i;
    rig?.setOrbColor(glows[i]);
    notifyListeners();
  }

  void trick() {
    if (asleep) {
      _wake();
      return;
    }
    _trickT = 1.1;
    _vel += const Offset(0, -320);
    fx?.sparkle(_world(_pos), vm.Vector3(1.0, 0.62, 0.2));
    _setStatus('Ta-da!', 2.5);
  }

  void emote() {
    const cycle = [Face.wink, Face.happy, Face.starry, Face.surprised, Face.talk];
    _emote = cycle[(cycle.indexOf(_emote) + 1) % cycle.length];
    _emoteT = 2.2;
    if (asleep) _wake();
    _setStatus(switch (_emote) {
      Face.wink => 'Lumi winks at you',
      Face.happy => 'Lumi is beaming',
      Face.starry => 'Lumi is starstruck',
      Face.surprised => 'Ooh!',
      _ => 'Lumi hums a tune',
    }, 2.5);
  }

  void setWeather(Weather w) {
    weather = w;
    rig?.showUmbrella = w == Weather.rain;
    rig?.showSnowman = w == Weather.snow;
    switch (w) {
      case Weather.clear:
        defaultStatus = 'Fireworks over the lagoon at 9:15';
        _setStatus('Clear skies for the show', 3);
      case Weather.rain:
        defaultStatus = 'Light rain from 10 PM';
        speak('Umbrella time!', 3);
      case Weather.snow:
        defaultStatus = 'Snow flurries tonight';
        speak('Snow! I made a friend.', 3.5);
    }
    notifyListeners();
  }

  /// Lumi talks in a bubble in place of the greeting.
  void speak(String text, double seconds) {
    speech = text;
    _speechT = seconds;
    notifyListeners();
  }

  /// Push-to-talk: listen briefly, then answer.
  Future<String> listen() async {
    if (asleep) _wake();
    listening = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1300));
    listening = false;
    final answers = weather == Weather.rain
        ? ['Umbrella time! The rain starts around 10.']
        : [
            'Star Swing is only 5 minutes right now. Quick, before it fills up!',
            'Fireworks start at 9:15. I know the best spot on the pier!',
            'Churros at Starlight Treats are still warm.',
          ];
    final a = answers[_noteCursor++ % answers.length];
    speak(a, 5);
    return a;
  }

  Future<void> collectKey() async {
    if (keys >= 5) {
      _setStatus('All 5 keys found!', 3);
      return;
    }
    keys++;
    _cheerT = 1.4;
    _trickT = 0.8;
    fx?.sparkle(_world(_pos), vm.Vector3(1.0, 0.7, 0.18), count: 110, power: 1.25);
    _starryT = 2.2;
    _setStatus('Key found! $keys of 5 collected', 4);
    notifyListeners();
  }

  void sendLumi() {
    if (away) return;
    if (asleep) _wake();
    away = true;
    _awayT = 0;
    _setStatus('Lumi is out looking for the key…', 999);
    notifyListeners();
  }

  void pushNote([ParkNote? n]) {
    final note = n ?? _noteDeck[_noteCursor++ % _noteDeck.length];
    final s = space;
    if (s == null) return;
    note.pos = Offset(s.size.width + 120, _pos.dy - 10);
    note.age = 0;
    note.eaten = false;
    note.done = false;
    notes.add(note);
  }

  static List<ParkNote> get _noteDeck => [
    ParkNote(
      'Treats',
      'Treats',
      'Warm glow churros at Starlight Treats',
      'Churros at Starlight Treats',
      Icons.notifications_rounded,
    ),
    ParkNote(
      'Reward',
      'Reward',
      'A new Lagoon Key is hiding nearby',
      'A Lagoon Key is hiding nearby',
      Icons.notifications_rounded,
    ),
    ParkNote('Show', 'Showtime', 'Fireworks over the lagoon in 20 min', 'Fireworks in 20 minutes', Icons.auto_awesome),
    ParkNote(
      'Ride',
      'Ride alert',
      'Star Swing wait dropped to 5 min',
      'Star Swing is down to 5 min',
      Icons.attractions_rounded,
    ),
  ];

  void _say(String s, double secs) => _setStatus(s, secs);

  void _setStatus(String s, double secs) {
    _status = s;
    _statusT = secs;
    notifyListeners();
  }

  // ======================= per-frame =======================

  void tick(double dt) {
    final r = rig;
    final s = space;
    if (r == null || s == null) return;
    dt = dt.clamp(0, 0.1);
    _t += dt;

    // timers
    if (_statusT > 0) {
      _statusT -= dt;
      if (_statusT <= 0 && _status.isNotEmpty) {
        _status = '';
        notifyListeners();
      }
    }
    if (_speechT > 0) {
      _speechT -= dt;
      if (_speechT <= 0) {
        speech = null;
        notifyListeners();
      }
    }
    _dizzyT -= dt;
    _eatT -= dt;
    _trickT -= dt;
    _surpriseT -= dt;
    _emoteT -= dt;
    _cheerT -= dt;
    _starryT -= dt;
    _holdT -= dt;
    _scrollIdle += dt;

    _petIdle += dt;
    if (_petting && _petIdle < 0.35 && !asleep && _dizzyT <= 0) {
      // Gentle, continuous petting slowly winds Lumi down.
      final before = _petCharge;
      _petCharge += dt;
      if (before < 2.2 && _petCharge >= 2.2) _say('Mmm… that’s nice', 2.5);
      if (_petCharge >= 4.5) _fallAsleep();
    } else if (_petIdle > 1.5) {
      _petCharge = math.max(0, _petCharge - dt * 0.6);
    }

    // friend swap: shrink, swap, pop back
    if (_swapT > 0) {
      _swapT -= dt;
      if (_swapT <= 0 && _pendingFriend != null) {
        friend = _pendingFriend!;
        _pendingFriend = null;
        r.setFriend(friend);
        r.setTint(tints[colorIndex]);
        r.setOrbColor(glows[glowIndex]);
        _scaleTarget = 1;
        _setStatus('Hi, I’m ${FriendStyle.styles[friend]!.name}!', 3);
        _cheerT = 0.8;
        notifyListeners();
      }
    }

    // scrollbar riding
    final wasRiding = riding;
    if (_scrollIdle < 0.25) {
      _scrollActive += dt;
    } else if (_scrollIdle > 1.1) {
      _scrollActive = 0;
    }
    riding = !away && !asleep && speech == null && _scrollActive > 0.3 && _scrollIdle < 1.1;
    if (riding != wasRiding) {
      if (riding) {
        _setStatus('Lumi is riding the scrollbar', 999);
      } else if (_status == 'Lumi is riding the scrollbar') {
        _setStatus('Wheee!', 1.5);
      }
    }

    // notifications
    if (notificationsOn && !away && !flying) {
      _noteTimer -= dt;
      if (_noteTimer <= 0 && notes.isEmpty) {
        pushNote();
        _noteTimer = 14 + _rnd.nextDouble() * 8;
      }
    }

    // ---------- target position ----------
    Offset target = home;
    _scaleTarget = _swapT > 0 ? 0.05 : 1;
    if (riding) {
      final sr = scrollRect;
      target = Offset(s.size.width - 16, sr.top + 26 + _scrollFrac * math.max(0, sr.height - 70));
      _scaleTarget = 0.3;
    }
    if (flying) {
      _flyT += dt;
      final f = _flyT;
      final tin = Curves.easeInOutCubic.transform((f / 1.5).clamp(0, 1));
      final tout = Curves.easeInOutCubic.transform(((f - _flyEnd - 0.3) / 1.5).clamp(0, 1));
      final k = tin - tout;
      pageTilt = _tiltMax * k;
      pageLift = 30 * k;
      pagePush = 210 * k;
      // The page is turned a little so its left edge and the slabs' sides
      // show, and turns a little more towards wherever Lumi is.
      final yawTo = (0.07 - 0.12 * ((_pos.dx - s.size.width / 2) / (s.size.width / 2))) * k;
      pageYaw += (yawTo - pageYaw) * (1 - math.exp(-dt * 2));
      _scaleTarget = 1 - 0.4 * k;

      // Hop from stop to stop once the page is most of the way back: crouch,
      // a ballistic arc up off the page, then squash on landing and spring
      // back while the card dips under it.
      final header = home + Offset(0, _footLength(r) * s.ppu * _scale);
      (Offset, double) stop(int i) {
        if (i < 0 || _stops[i].$2 < 0) return (header, -headerLift / s.ppu * k);
        final (at, _, lift, spread) = _stops[i];
        return (at + Offset(0, spread * k), -lift / s.ppu * k);
      }

      var lift = 0.0, lean = 0.0;
      var standingOn = -1;
      if (f < 1.1) {
        _feet = header;
        _feetZ = 0;
      } else if (_leg >= _stops.length) {
        _feet = header;
        _feetZ = 0;
      } else {
        _legT += dt;
        final (p0, z0) = stop(_leg - 1);
        final (p1, z1) = stop(_leg);
        final dist = (p1 - p0).distance / s.ppu;
        final air = 0.42 + 0.08 * dist;
        final height = 0.85 + 0.22 * dist;
        final t = _legT;
        if (t < _crouch) {
          _feet = p0;
          _feetZ = z0;
          standingOn = _leg > 0 ? _stops[_leg - 1].$2 : -1;
          r.squashY = 0.72;
        } else if (t < _crouch + air) {
          final u = (t - _crouch) / air;
          final e = u * 0.7 + Curves.easeInOutSine.transform(u) * 0.3;
          _feet = Offset.lerp(p0, p1, e)!;
          lift = 4 * u * (1 - u);
          _feetZ = z0 + (z1 - z0) * e;
          _hopUp = height * lift;
          // Stretch on the way up, round at the top, stretch into the fall.
          r.squashY = u < 0.5 ? 1.18 - 0.36 * u : 1.0 + 0.24 * (u - 0.5);
          lean = ((p1.dx - p0.dx) / s.size.width).clamp(-1.0, 1.0) * -0.35 * (1 - u);
        } else {
          final card = _stops[_leg].$2;
          if (!_landed) {
            _landed = true;
            r.squashY = 0.68;
            if (card >= 0) cardPress[card] = 1;
          }
          _feet = p1;
          _feetZ = z1;
          standingOn = card;
          final since = t - _crouch - air;
          if (since > 0.08) r.squashY = since < _land ? 1.07 : 1.0;
          final last = _leg == _stops.length - 1;
          if (since >= _land + (last ? 0 : _dwell)) {
            _leg++;
            _legT = 0;
            _landed = false;
            if (_leg == _stops.length) _flyEnd = f;
          }
        }
      }
      if (lift == 0) _hopUp = 0;
      _hopLift = lift;
      _hopLean = lean;
      // Cards spring back up, but stay a little pressed under Lumi.
      for (final i in cardPress.keys.toList()) {
        final rest = i == standingOn ? 0.35 : 0.0;
        cardPress[i] = rest + (cardPress[i]! - rest) * math.exp(-dt * 7);
      }
      target = _feet;
      if (f >= _flyEnd + 1.8) {
        _flyT = -1;
        pageTilt = pageYaw = pageLift = pagePush = 0;
        _hopLift = _hopLean = _hopUp = 0;
        cardPress.clear();
        _pos = home;
        _vel = Offset.zero;
        _setStatus('That was fun!', 2.5);
        notifyListeners();
      }
    }
    if (away) {
      _awayT += dt;
      if (_awayT < 2.6) {
        target = Offset(s.size.width + 140, home.dy - 60);
      } else if (_awayT > 2.6 && _awayT < 2.7) {
        _pos = Offset(-140, home.dy - 40);
      } else {
        target = home;
        if ((_pos - home).distance < 14) {
          away = false;
          collectKey();
        }
      }
    }
    final idleBob = Offset(0, math.sin(_t * 1.6) * 6 * (asleep ? 0.6 : 1));
    final sway = Offset(math.sin(_t * 0.5) * 4, 0);
    var goal = target + (riding || flying ? Offset.zero : idleBob + sway);

    // Eating: lean toward the note being eaten.
    ParkNote? active;
    for (final n in notes) {
      if (!n.done) {
        active = n;
        break;
      }
    }

    // spring
    final stiffness = riding ? 140.0 : (away ? 30.0 : 70.0);
    const damping = 11.0;
    final acc = (goal - _pos) * stiffness - _vel * damping;
    _vel += acc * dt;
    _pos += _vel * dt;
    if (flying) _pos = goal; // the hops are already the motion
    _scale += (_scaleTarget - _scale) * (1 - math.exp(-dt * (_swapT > 0 ? 18 : 8)));

    // ---------- notes ----------
    for (final n in notes) {
      _tickNote(n, dt);
    }
    notes.removeWhere((n) => n.done);

    // ---------- face & body ----------
    Face face = Face.idle;
    double glow = 1, blush = 0, tilt = 0, spin = 0, hands = 0;
    var gaze = vm.Vector2.zero();

    if (_pointer != null && !asleep) {
      final d = _pointer! - _pos;
      gaze = vm.Vector2((d.dx / 220).clamp(-1, 1), (d.dy / 260).clamp(-1, 1));
    }
    if (active != null && !asleep) {
      final d = active.pos - _pos;
      gaze = vm.Vector2((d.dx / 120).clamp(-1, 1), (d.dy / 200).clamp(-1, 1));
    }

    if (_emoteT > 0) face = _emote;
    if (speech != null) face = Face.talk;
    if (_petting || _petCharge > 0.3) {
      face = _petCharge > 2.2 ? Face.sleepy : Face.happy;
      blush = (0.4 + _petCharge / 4).clamp(0, 1);
      tilt = math.sin(_t * 2) * 0.12;
      glow = 1 - (_petCharge / 4.5) * 0.25;
    }
    if (_surpriseT > 0) face = Face.surprised;
    if (_trickT > 0) {
      face = Face.happy;
      spin = (1 - (_trickT / 1.1).clamp(0, 1)) * math.pi * 2;
      hands = 1;
    }
    if (_cheerT > 0) hands = 1;
    if (_holdT > 0) {
      hands = math.max(hands, 0.55);
      gaze = vm.Vector2(gaze.x * 0.3, 0.8);
    }
    if (flying) {
      face = Face.happy;
      hands = 0.25 + 0.6 * _hopLift;
      tilt = _hopLean;
      gaze = vm.Vector2(0, 0.6);
    }
    if (_starryT > 0) face = Face.starry;
    if (_eatT > 0) {
      face = Face.munch;
      blush = 0.5;
    }
    if (_dizzyT > 0) {
      face = Face.dizzy;
      tilt = math.sin(_t * 9) * 0.35;
      gaze = vm.Vector2(math.sin(_t * 7), math.cos(_t * 7)) * 0.6;
    }
    if (asleep) {
      face = Face.asleep;
      glow = 0.62 + 0.08 * math.sin(_t * 1.2);
      tilt = 0.18;
      blush = 0.25;
      if (_rnd.nextDouble() < dt * 0.9) zzz.add(_Zed(_pos + Offset(headRadiusPx * 0.7, -headRadiusPx * 0.8)));
    }
    if (riding) face = Face.happy;

    // Breathing squash when idle.
    if (r.squashY > 0.95 && r.squashY < 1.05) {
      r.squashY = 1 + math.sin(_t * (asleep ? 1.2 : 2.2)) * (asleep ? 0.035 : 0.018);
    }

    r
      ..face = face
      ..gaze = gaze
      ..glow = glow
      ..blush = blush
      ..tilt = tilt
      ..spin = spin
      ..handsUp = hands;
    r.update(dt);

    // Place in 3D. Turned against the page's tilt so Lumi stays upright
    // and facing us while the page tips back; while hopping, stood with its
    // feet on the card (or the header) instead of centred on _pos.
    final turn = vm.Quaternion.fromRotation(
      (vm.Matrix4.rotationX(-pageTilt)..multiply(vm.Matrix4.rotationY(-pageYaw))).getRotation(),
    );
    r.root.rotation = turn;
    r.root.position = flying
        ? s.toWorld(_feet) + vm.Vector3(0, 0, _feetZ) + turn.rotated(vm.Vector3(0, _footLength(r) * _scale + _hopUp, 0))
        : s.toWorld(_pos);
    r.root.scale = vm.Vector3.all(_scale.clamp(0.001, 2));

    sparks?.node.visible = ambientSparks;
    sparks?.update(dt);
    if (sparks != null) {
      // keep sparks within the header band
      final top = s.toWorld(headerRect.topLeft);
      final bottom = s.toWorld(headerRect.bottomRight);
      sparks!.area = vm.Aabb3.minMax(vm.Vector3(top.x, bottom.y, -0.6), vm.Vector3(bottom.x, top.y, 2.5));
    }

    fx?.update(dt);

    // 2D particles
    for (final z in zzz) {
      z.age += dt;
    }
    zzz.removeWhere((z) => z.age > 2.6);
    for (final h in hearts) {
      h.age += dt;
    }
    hearts.removeWhere((h) => h.age > 1.4);

    frame.value++;
  }

  /// Flies a note in from the right, lets Lumi catch it in its hands, tip
  /// it over and swallow it; the card ends up inside the glass head, where
  /// it shrinks away.
  void _tickNote(ParkNote n, double dt) {
    final s = space!;
    final card = n.card;
    if (card == null) {
      if (!n._loading) {
        n._loading = true;
        NoteCard.create(n.title, n.body, n.icon).then(
          (c) {
            n.card = c;
            scene.add(c.node);
          },
          onError: (Object _) {
            n.done = true;
          },
        );
      }
      return;
    }
    n.age += dt;
    final hr = headRadiusPx;
    const arrive = 0.7, hold = 1.4, tip = 0.8, gulp = 0.5, digest = 0.6;

    // Poses: screen position, depth (negative is towards the camera),
    // yaw, pitch, roll, scale.
    final restX = math.min(_pos.dx + hr + 72, s.size.width - NoteCard.size.width * _scale * 0.45);
    final rest = (Offset(restX, _pos.dy - 8), -0.2, 0.45, 0.0, 0.0, 1.0);
    final held = (_pos + Offset(0, hr * 1.12), -0.8, 0.12, 0.55, 0.12, 0.86);
    // Tipped up on Lumi's left, one corner at the mouth, like the video.
    final tipped = (_pos + Offset(-hr * 0.85, hr * 0.8), -0.7, -0.15, 0.35, 0.95, 0.78);
    final mouth = (_pos + Offset(-hr * 0.5, hr * 0.5), -0.5, -0.1, 0.45, 1.0, 0.62);
    final inside = (_pos + Offset(-hr * 0.05, -hr * 0.05), 0.05, 0.0, 0.6, 1.25, 0.32);
    final enter = (Offset(s.size.width + 160, _pos.dy - 30), -0.2, 1.3, 0.0, 0.25, 1.0);
    final drift = (Offset(rest.$1.dx + 30, rest.$1.dy - 50), -0.2, 0.7, 0.0, 0.1, 1.0);

    (Offset, double, double, double, double, double) lerp(
      (Offset, double, double, double, double, double) a,
      (Offset, double, double, double, double, double) b,
      double t,
    ) {
      double l(double x, double y) => x + (y - x) * t;
      return (Offset.lerp(a.$1, b.$1, t)!, l(a.$2, b.$2), l(a.$3, b.$3), l(a.$4, b.$4), l(a.$5, b.$5), l(a.$6, b.$6));
    }

    var pose = rest;
    var opacity = 1.0;
    var front = 1.0;
    final g = n.age;
    if (asleep || away) {
      // Nobody to eat it: it drifts past and fades.
      pose = lerp(rest, drift, (g / 4).clamp(0, 1));
      opacity = (g < 3 ? 1.0 : 4 - g).clamp(0, 1);
      if (g > 4) n.done = true;
    } else if (g < arrive) {
      pose = lerp(enter, rest, Curves.easeOutBack.transform(g / arrive));
      opacity = (g / 0.2).clamp(0, 1);
      if (g + dt >= arrive * 0.5 && g < arrive * 0.5) _surpriseT = 0.6;
    } else if (g < arrive + hold) {
      // Catch it, then hold it up in front of the body.
      final t = Curves.easeInOutCubic.transform(((g - arrive) / 0.5).clamp(0, 1));
      pose = lerp(rest, held, t);
      final bob = math.sin(g * 3) * 3;
      pose = (pose.$1 + Offset(0, bob), pose.$2, pose.$3, pose.$4 + math.sin(g * 2.3) * 0.05, pose.$5, pose.$6);
      _holdT = 0.3;
    } else if (g < arrive + hold + tip) {
      // Tip it up to the mouth and nibble the corner in.
      final t = (g - arrive - hold) / tip;
      pose = t < 0.6
          ? lerp(held, tipped, Curves.easeInOutCubic.transform(t / 0.6))
          : lerp(tipped, mouth, Curves.easeInOut.transform((t - 0.6) / 0.4));
      _holdT = 0.3;
      if (t > 0.6) _eatT = 1.3;
    } else if (g < arrive + hold + tip + gulp) {
      if (!n.eaten) {
        n.eaten = true;
        _cheerT = 0.4;
      }
      final t = (g - arrive - hold - tip) / gulp;
      pose = lerp(mouth, inside, Curves.easeInCubic.transform(t));
      _eatT = 1.3;
      // Past the lips it is behind the glass: hand over to the glowing card.
      front = 1 - (t / 0.35).clamp(0.0, 1.0);
    } else if (g < arrive + hold + tip + gulp + digest) {
      // Inside the head: it tumbles and dissolves.
      final t = (g - arrive - hold - tip - gulp) / digest;
      front = 0;
      pose = (inside.$1, inside.$2, inside.$3 + t * 1.4, inside.$4, inside.$5 + t * 0.8, inside.$6 * (1 - t));
      opacity = 1 - t * t;
    } else {
      n.done = true;
      front = opacity = 0;
      _eatT = 1.3;
      rig?.squashY = 1.15;
      Future.delayed(const Duration(milliseconds: 160), () => rig?.squashY = 0.92);
      Future.delayed(const Duration(milliseconds: 320), () => rig?.squashY = 1.0);
      _setStatus(n.after, 4);
      fx?.puff(_world(_pos + Offset(-hr * 0.2, hr * 0.3), -0.5), vm.Vector3(1.0, 0.6, 0.25));
    }

    final (at, depth, yaw, pitch, roll, size) = pose;
    n.pos = at;
    card.node
      ..position = _world(at, depth)
      ..rotation =
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw) *
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -pitch) *
          vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), roll)
      ..scale = vm.Vector3.all(math.max(0.001, size * _scale));
    n.opacity = opacity;
    n.front = front;
    card.opacity = opacity * (1 - front);
    if (n.done) card.node.detach();
  }

  @override
  void dispose() {
    frame.dispose();
    super.dispose();
  }
}

class _Zed {
  _Zed(this.origin);
  final Offset origin;
  double age = 0;
}

class _Heart {
  _Heart(this.origin);
  final Offset origin;
  double age = 0;
}

/// Read-only views of the 2D particles for painters.
extension LumiParticles on LumiBrain {
  Iterable<(Offset, double)> get zeds => zzz.map((z) => (z.origin, z.age));
  Iterable<(Offset, double)> get heartList => hearts.map((h) => (h.origin, h.age));
}
