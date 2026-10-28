import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/lumi_rig.dart';
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
  Offset pos = Offset.zero;
  double scale = 1;
  double turn = 0; // rotation in radians
  double tiltY = 0; // perspective swing
  double opacity = 0;
  bool eaten = false;
  bool done = false;
}

/// A burst of 2D sparkles painted around Lumi (tricks, friend swaps, keys).
class Burst {
  Burst(this.center, this.color, {this.rings = 1, this.count = 28});
  final Offset center;
  final Color color;
  final int rings;
  final int count;
  double age = 0;
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
  final bursts = <Burst>[];
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

  Offset get lumiPos => _pos;
  double get lumiScale => _scale;
  double get headRadiusPx => (rig?.style.headRadius ?? 0.56) * (space?.ppu ?? 100) * _scale;
  double get petProgress => (_petCharge / 4.5).clamp(0, 1);

  Future<void> init() async {
    await Scene.initializeStaticResources();
    scene.toneMapping = ToneMappingMode.linear;
    final r = await LumiRig.create();
    scene.add(r.root);
    final s = Sparks(
      22,
      size: 0.022,
      area: vm.Aabb3.minMax(vm.Vector3(-2.2, 0.6, -0.6), vm.Vector3(2.2, 4.2, 2.5)),
    );
    scene.add(s.node);
    sparks = s;
    rig = r;
    notifyListeners();
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
      _roughness += d / 220;
      if (_roughness > 1.0 && _dizzyT <= 0) _getDizzy();
    } else if (d > 0.5) {
      _petIdle = 0;
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
  }

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
    bursts.add(Burst(_pos, const Color(0xFFFFD27A), rings: 2, count: 36));
    _setStatus('Ta-da!', 2.5);
  }

  void emote() {
    const cycle = [Face.wink, Face.happy, Face.surprised, Face.talk];
    _emote = cycle[(cycle.indexOf(_emote) + 1) % cycle.length];
    _emoteT = 2.2;
    if (asleep) _wake();
    _setStatus(switch (_emote) {
      Face.wink => 'Lumi winks at you',
      Face.happy => 'Lumi is beaming',
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
    bursts.add(Burst(_pos, const Color(0xFFFFC34D), rings: 2, count: 40));
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
    ParkNote(
      'Show',
      'Showtime',
      'Fireworks over the lagoon in 20 min',
      'Fireworks in 20 minutes',
      Icons.auto_awesome,
    ),
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
        bursts.add(Burst(_pos, const Color(0xFFFFE3A3), count: 30));
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
    if (notificationsOn && !away) {
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
    var goal = target + (riding ? Offset.zero : idleBob + sway);

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

    // place in 3D
    r.root.position = s.toWorld(_pos - Offset(0, 0));
    r.root.scale = vm.Vector3.all(_scale.clamp(0.001, 2));

    sparks?.node.visible = ambientSparks;
    sparks?.update(dt);
    if (sparks != null) {
      // keep sparks within the header band
      final top = s.toWorld(headerRect.topLeft);
      final bottom = s.toWorld(headerRect.bottomRight);
      sparks!.area = vm.Aabb3.minMax(vm.Vector3(top.x, bottom.y, -0.6), vm.Vector3(bottom.x, top.y, 2.5));
    }

    // 2D particles
    for (final b in bursts) {
      b.age += dt;
    }
    bursts.removeWhere((b) => b.age > 1.4);
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

  void _tickNote(ParkNote n, double dt) {
    n.age += dt;
    final s = space!;
    final rest = Offset(math.min(s.size.width - 92, _pos.dx + headRadiusPx + 72), _pos.dy - 6);
    final mouth = _pos + Offset(0, headRadiusPx * 0.3);
    const arrive = 0.7, hold = 1.7, gulp = 0.55;
    if (asleep || away) {
      // nobody to eat it: drift past and fade
      n.pos = Offset.lerp(n.pos, Offset(rest.dx, rest.dy - 40), 1 - math.exp(-dt * 3))!;
      n.opacity = (n.age < 3 ? 1.0 : (1 - (n.age - 3))).clamp(0, 1);
      n.tiltY = 0.25;
      if (n.age > 4) n.done = true;
      return;
    }
    if (n.age < arrive) {
      final t = Curves.easeOutBack.transform(n.age / arrive);
      n.pos = Offset.lerp(Offset(s.size.width + 140, rest.dy), rest, t)!;
      n.opacity = (n.age / 0.25).clamp(0, 1);
      n.tiltY = (1 - t) * 0.9;
      n.turn = 0;
      if (n.age + dt >= arrive * 0.5 && n.age < arrive * 0.5) _surpriseT = 0.6;
    } else if (n.age < arrive + hold) {
      n.pos = rest + Offset(0, math.sin(n.age * 3) * 2);
      n.tiltY = 0.12;
      n.opacity = 1;
    } else if (n.age < arrive + hold + gulp) {
      if (!n.eaten) {
        n.eaten = true;
        _cheerT = 0.4;
      }
      final t = Curves.easeInCubic.transform((n.age - arrive - hold) / gulp);
      n.pos = Offset.lerp(rest, mouth, t)!;
      n.scale = 1 - t * 0.95;
      n.turn = -t * 1.1;
      n.tiltY = 0.12 + t * 0.6;
      n.opacity = 1 - t * 0.6;
      if (t > 0.6) _eatT = 1.3;
    } else {
      n.done = true;
      _eatT = 1.3;
      rig?.squashY = 1.15;
      Future.delayed(const Duration(milliseconds: 160), () => rig?.squashY = 0.92);
      Future.delayed(const Duration(milliseconds: 320), () => rig?.squashY = 1.0);
      _setStatus(n.after, 4);
      bursts.add(Burst(mouth, const Color(0xFFFFB86B), count: 14));
    }
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
