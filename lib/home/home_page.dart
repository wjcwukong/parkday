import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';

import '../lumi/lumi_brain.dart';
import '../scene/lumi_rig.dart';
import '../scene/note_card.dart';
import '../screens/fireworks_show.dart';
import '../screens/lumi_room.dart';
import '../screens/park_map.dart';
import '../screens/sky_lift.dart';
import '../screens/star_catch.dart';
import '../theme.dart';
import '../widgets/light_layer.dart';
import '../widgets/painters.dart';
import 'feed.dart';
import 'wardrobe.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final brain = LumiBrain();
  late final AnimationController clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))
    ..repeat();
  final scroll = ScrollController();
  final search = TextEditingController();
  final waitKey = GlobalKey();
  String query = '';
  bool wardrobe = false;
  bool paused = false;
  String? highlightRide;
  int skyBest = 1222;

  @override
  void initState() {
    super.initState();
    brain.init();
    brain.addListener(_onBrain);
  }

  void _onBrain() => setState(() {});

  @override
  void dispose() {
    brain.removeListener(_onBrain);
    brain.dispose();
    clock.dispose();
    scroll.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> _push(Widget page) async {
    setState(() => paused = true);
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
    if (mounted) setState(() => paused = false);
  }

  Future<void> _mic() async {
    final answer = await brain.listen();
    if (answer.contains('Star Swing')) {
      final ctx = waitKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
          alignment: 0.1,
        );
        if (mounted) setState(() => highlightRide = 'Star Swing');
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) setState(() => highlightRide = null);
      }
    }
  }

  void _collect(Offset from) {
    // A key coin hops from the button to Lumi, then Lumi celebrates.
    final overlay = Overlay.of(context);
    late OverlayEntry e;
    e = OverlayEntry(
      builder: (_) => _FlyingKey(
        from: from,
        to: () => brain.lumiPos,
        onDone: () {
          e.remove();
          brain.collectKey();
        },
      ),
    );
    overlay.insert(e);
  }

  void _photo() async {
    brain.speak('Say cheese!', 1.6);
    brain.emote();
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final overlay = Overlay.of(context);
    late OverlayEntry e;
    e = OverlayEntry(
      builder: (_) => _PhotoFlash(brain: brain, onDone: () => e.remove()),
    );
    overlay.insert(e);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pd.bgDeep,
      body: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          final pad = MediaQuery.paddingOf(context).top;
          const barH = 46.0, stageH = 196.0, greetH = 66.0;
          final headerH = pad + barH + stageH + greetH;
          brain.layout(size);
          brain.home = Offset(size.width / 2, pad + barH + 86);
          brain.headerRect = Rect.fromLTWH(0, 0, size.width, headerH);
          brain.scrollRect = Rect.fromLTWH(0, headerH, size.width, size.height - headerH);
          final friendName = brain.rig?.style.name ?? 'Lumi';

          return Stack(
            children: [
              // The page itself: everything here tips back into 3D together
              // during Lumi's fly-over.
              Positioned.fill(
                child: _PageTilt(
                  brain: brain,
                  child: Stack(
                    children: [
                      Positioned.fill(child: CustomPaint(painter: StarfieldPainter(clock))),
                      // ---------------- feed ----------------
                      Positioned(
                        top: headerH,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRect(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n is ScrollUpdateNotification && n.depth == 0) {
                                final m = n.metrics;
                                final f = m.maxScrollExtent <= 0 ? 0.0 : m.pixels / m.maxScrollExtent;
                                brain.onScroll(f, true);
                              }
                              return false;
                            },
                            child: Scrollbar(
                              controller: scroll,
                              child: ListView(
                                controller: scroll,
                                padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
                                children: [
                                  _Slab(
                                    brain: brain,
                                    radius: 12,
                                    child: SearchBox(controller: search, onChanged: (v) => setState(() => query = v)),
                                  ),
                                  const SizedBox(height: 12),
                                  if (query.isNotEmpty)
                                    SearchResults(query: query)
                                  else ...[
                                    _Slab(
                                      brain: brain,
                                      child: FireworksCard(
                                        t: clock,
                                        friendName: friendName,
                                        onWatch: () => _push(FireworksShow(brain: brain)),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _Slab(
                                      brain: brain,
                                      child: RewardCard(brain: brain, onCollect: _collect),
                                    ),
                                    const SizedBox(height: 12),
                                    _Slab(
                                      brain: brain,
                                      child: WeatherCard(brain: brain),
                                    ),
                                    const SizedBox(height: 12),
                                    _Slab(
                                      brain: brain,
                                      child: PhotoBoothCard(onTap: _photo, friendName: friendName),
                                    ),
                                    const SizedBox(height: 12),
                                    _Slab(
                                      brain: brain,
                                      child: PlayCard(
                                        t: clock,
                                        stars: 31,
                                        best: skyBest,
                                        friendName: friendName,
                                        onStarCatch: () => _push(StarCatchGame(brain: brain)),
                                        onSkyLift: () async {
                                          await _push(
                                            SkyLiftGame(
                                              brain: brain,
                                              onBest: (m) {
                                                if (m > skyBest) skyBest = m;
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _Slab(
                                      brain: brain,
                                      child: ParkMapCard(
                                        friendName: friendName,
                                        onOpen: () => _push(ParkMapScreen(brain: brain)),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _Slab(
                                      brain: brain,
                                      child: WaitTimesCard(key: waitKey, highlight: highlightRide),
                                    ),
                                    const SizedBox(height: 12),
                                    _Slab(brain: brain, child: const DiningCard()),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ---------------- wardrobe panel ----------------
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutCubic,
                        top: wardrobe ? headerH - 8 : size.height + 20,
                        left: 0,
                        right: 0,
                        height: size.height - headerH + 8,
                        child: WardrobePanel(brain: brain, onClose: () => setState(() => wardrobe = false)),
                      ),
                      // ---------------- header ----------------
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: headerH,
                        child: IgnorePointer(child: CustomPaint(painter: WeatherPainter(clock, brain.weather))),
                      ),
                      Positioned(
                        top: pad,
                        left: 0,
                        right: 0,
                        height: barH,
                        child: _TopBar(
                          brain: brain,
                          onWardrobe: () => setState(() => wardrobe = !wardrobe),
                          onSettings: () => _settings(context),
                        ),
                      ),
                      Positioned(
                        top: pad + barH + stageH,
                        left: 0,
                        right: 0,
                        height: greetH,
                        child: _Greeting(
                          brain: brain,
                          onMic: _mic,
                          onTrick: brain.trick,
                          onRoom: () => _push(LumiRoom(brain: brain)),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(child: CustomPaint(painter: _LightPoolPainter(brain))),
                      ),
                    ],
                  ),
                ),
              ),
              // ---------------- Lumi ----------------
              if (brain.ready && !paused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: LightLayer(
                      child: SceneView(
                        brain.scene,
                        cameraBuilder: (_) => brain.camera,
                        onTick: (_, dt) => brain.tick(dt),
                      ),
                    ),
                  ),
                ),
              if (brain.ready && !paused) Positioned.fill(child: IgnorePointer(child: _NoteOverlay(brain: brain))),
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: LumiAuraPainter(brain, front: true))),
              ),
              // pointer sensing for petting and gaze, without stealing scrolls
              Positioned(
                top: pad + barH - 10,
                left: 0,
                right: 0,
                height: stageH + 20,
                child: _LumiTouch(brain: brain),
              ),
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerHover: (e) => brain.pointerHover(e.position),
                  onPointerMove: (e) => brain.pointerHover(e.position),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _settings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151937),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget sw(String title, String sub, bool v, ValueChanged<bool> on) => SwitchListTile(
            value: v,
            onChanged: (x) {
              on(x);
              set(() {});
            },
            activeThumbColor: Pd.lumiBlue,
            title: Text(title, style: Pd.t(14, w: FontWeight.w600)),
            subtitle: Text(sub, style: Pd.t(11.5, c: Pd.textDim)),
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Settings', style: Pd.t(16, w: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  sw(
                    'Park notifications',
                    'Lumi eats them when they arrive',
                    brain.notificationsOn,
                    (x) => brain.notificationsOn = x,
                  ),
                  sw(
                    'Floating sparks',
                    'Embers drifting around the header',
                    brain.ambientSparks,
                    (x) => brain.ambientSparks = x,
                  ),
                  ListTile(
                    title: Text('Send a test notification', style: Pd.t(14, w: FontWeight.w600)),
                    trailing: const Icon(Icons.notifications_active_rounded, color: Pd.gold),
                    onTap: () {
                      Navigator.pop(ctx);
                      brain.pushNote();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text('Built with Flutter Scene · fscene.dev', style: Pd.t(11, c: Pd.textFaint)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.brain, required this.onWardrobe, required this.onSettings});
  final LumiBrain brain;
  final VoidCallback onWardrobe;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    Widget dot(Friend f, List<Color> colors) => GestureDetector(
      onTap: () => brain.setFriend(f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(left: 6),
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: const Alignment(-0.3, -0.4), colors: colors),
          border: Border.all(
            color: brain.friend == f ? Colors.white : Colors.white24,
            width: brain.friend == f ? 1.6 : 1,
          ),
        ),
      ),
    );
    Widget icon(IconData i, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Icon(i, size: 20, color: Pd.text),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Tapping the wordmark sends Lumi on a fly-over of the page.
          GestureDetector(
            onTap: brain.flyover,
            child: Text('Parkday', style: Pd.t(14.5, w: FontWeight.w700)),
          ),
          const Spacer(),
          dot(Friend.lumi, const [Color(0xFFCDE7FF), Color(0xFF5EA8FF)]),
          dot(Friend.juju, const [Color(0xFFFFC2B0), Color(0xFFFF6F55)]),
          dot(Friend.mochi, const [Color(0xFFE9FFF4), Color(0xFF9DEBCF)]),
          const SizedBox(width: 2),
          icon(Icons.sentiment_satisfied_alt_rounded, brain.emote),
          icon(Icons.checkroom_rounded, onWardrobe),
          icon(Icons.tune_rounded, onSettings),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.brain, required this.onMic, required this.onTrick, required this.onRoom});
  final LumiBrain brain;
  final VoidCallback onMic;
  final VoidCallback onTrick;
  final VoidCallback onRoom;

  @override
  Widget build(BuildContext context) {
    final speech = brain.speech;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              layoutBuilder: _leftLayout,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: speech != null
                  ? _SpeechBubble(key: ValueKey(speech), text: speech)
                  : Column(
                      key: const ValueKey('greet'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(), style: Pd.t(21, w: FontWeight.w700, ls: -0.2)),
                        const SizedBox(height: 3),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          layoutBuilder: _leftLayout,
                          child: Text(
                            brain.status,
                            key: ValueKey(brain.status),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Pd.t(11, c: Pd.textDim),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 8),
          _PulsingMic(active: brain.listening, onTap: onMic),
          const SizedBox(width: 9),
          RoundIcon(icon: Icons.auto_awesome, onTap: onTrick),
          const SizedBox(width: 9),
          RoundIcon(icon: Icons.home_rounded, onTap: onRoom),
        ],
      ),
    );
  }

  // Keep the greeting pinned left while texts cross-fade.
  static Widget _leftLayout(Widget? current, List<Widget> previous) =>
      Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]);

  // Parkday is a night-time park: the demo always greets you for the evening.
  String _greeting() => 'Good evening';
}

class _PulsingMic extends StatefulWidget {
  const _PulsingMic({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;
  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(covariant _PulsingMic old) {
    super.didUpdateWidget(old);
    if (widget.active && !c.isAnimating) c.repeat();
    if (!widget.active) c.stop();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            if (widget.active)
              BoxShadow(
                color: const Color(0xFF8FC8FF).withValues(alpha: 0.6 * (1 - c.value)),
                blurRadius: 4,
                spreadRadius: 10 * c.value,
              ),
          ],
        ),
        child: child,
      ),
      child: RoundIcon(icon: Icons.mic_rounded, active: widget.active, onTap: widget.onTap),
    );
  }
}

class _SpeechBubble extends StatefulWidget {
  const _SpeechBubble({super.key, required this.text});
  final String text;
  @override
  State<_SpeechBubble> createState() => _SpeechBubbleState();
}

class _SpeechBubbleState extends State<_SpeechBubble> with SingleTickerProviderStateMixin {
  late final c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 28 * widget.text.length + 100),
  )..forward();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: CustomPaint(
        painter: _BubbleTail(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF232955),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x22FFFFFF)),
          ),
          child: AnimatedBuilder(
            animation: c,
            builder: (_, _) {
              final n = (widget.text.length * c.value).round();
              return Text(
                widget.text.substring(0, n),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Pd.t(10.5, w: FontWeight.w600, h: 1.28),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * 0.72;
    final p = Path()
      ..moveTo(x - 7, 1)
      ..lineTo(x + 4, -9)
      ..lineTo(x + 6, 1)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFF232955));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Catches touches on Lumi (pet, poke) and lets everything else through.
class _LumiTouch extends StatelessWidget {
  const _LumiTouch({required this.brain});
  final LumiBrain brain;

  @override
  Widget build(BuildContext context) {
    return _LumiHitArea(
      brain: brain,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => brain.pointerDown(e.position, e.timeStamp),
        onPointerMove: (e) => brain.pointerMove(e.position, e.timeStamp),
        onPointerUp: (e) => brain.pointerUp(e.position, e.timeStamp),
        onPointerCancel: (e) => brain.pointerUp(e.position, e.timeStamp),
      ),
    );
  }
}

class _LumiHitArea extends SingleChildRenderObjectWidget {
  const _LumiHitArea({required this.brain, super.child});
  final LumiBrain brain;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLumiHit(brain);
  @override
  void updateRenderObject(BuildContext context, _RenderLumiHit r) => r.brain = brain;
}

class _RenderLumiHit extends RenderProxyBox {
  _RenderLumiHit(this.brain);
  LumiBrain brain;
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final global = localToGlobal(position);
    if (!brain.hitsLumi(global)) return false;
    return super.hitTest(result, position: position);
  }
}

/// Tips the page back by [LumiBrain.pageTilt] with the same perspective as
/// the overlay scene's camera (eye at the camera distance, centered), so
/// Lumi and its light stay in register with the tilted widgets.
class _PageTilt extends StatelessWidget {
  const _PageTilt({required this.brain, required this.child});
  final LumiBrain brain;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: brain.frame,
      child: child,
      builder: (context, _, child) {
        return IgnorePointer(
          ignoring: brain.flying,
          child: Transform(alignment: Alignment.center, transform: brain.pageMatrix, child: child),
        );
      },
    );
  }
}

/// While the page is tipped back, lifts a card off it as a thick slab, the
/// way the original's cards stand up from the page during the fly-over.
/// The slab's sides are a few stacked copies of its outline, and the card
/// itself rides on top; flat, it is just the card.
class _Slab extends StatelessWidget {
  const _Slab({required this.brain, required this.child, this.radius = 14});
  final LumiBrain brain;
  final Widget child;
  final double radius;

  static const _depth = 16.0, _layers = 5;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: brain.frame,
      child: child,
      builder: (context, _, child) {
        final k = brain.tiltAmount;
        final r = BorderRadius.circular(radius);
        Matrix4 up(double z) => Matrix4.translationValues(0, 0, -z);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (k > 0) ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: r,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55 * k),
                        blurRadius: 16,
                        offset: Offset(0, 8 * k),
                      ),
                    ],
                  ),
                ),
              ),
              for (var i = 0; i < _layers; i++)
                Positioned.fill(
                  child: Transform(
                    transform: up(_depth * k * i / _layers),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.lerp(const Color(0xFF07081A), const Color(0xFF181C3E), i / _layers),
                        borderRadius: r,
                      ),
                    ),
                  ),
                ),
            ],
            Transform(key: const ValueKey('card'), transform: up(_depth * k), child: child),
          ],
        );
      },
    );
  }
}

/// The solid note cards Lumi holds in front of itself. The home scene is
/// screen-blended onto the page, so a dark card in it would vanish; this
/// draws the card as a widget on top instead, in the same perspective as
/// the scene's card (the camera's projection times the card's world
/// transform), and the scene's glowing card takes over once it is past
/// Lumi's lips.
class _NoteOverlay extends StatelessWidget {
  const _NoteOverlay({required this.brain});
  final LumiBrain brain;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: brain.frame,
      builder: (context, _, _) {
        final sp = brain.space;
        if (sp == null) return const SizedBox.shrink();
        final cards = <Widget>[];
        for (final n in brain.notes) {
          final card = n.card;
          final k = n.opacity * n.front;
          if (card == null || n.done || k <= 0.01) continue;
          final size = NoteCard.size;
          final m = Matrix4.identity()
            ..setEntry(3, 2, 1 / (sp.distance * sp.ppu))
            ..multiply(Matrix4.diagonal3Values(sp.ppu, -sp.ppu, sp.ppu))
            ..multiply(Matrix4.fromList(card.node.globalTransform.storage))
            ..multiply(Matrix4.diagonal3Values(0.01, -0.01, 1))
            ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
          cards.add(
            Positioned(
              left: sp.size.width / 2,
              top: sp.size.height / 2,
              child: Transform(
                transform: m,
                child: Opacity(
                  opacity: k.clamp(0.0, 1.0),
                  child: CustomPaint(size: size, painter: _NoteFacePainter(n)),
                ),
              ),
            ),
          );
        }
        return Stack(clipBehavior: Clip.none, children: cards);
      },
    );
  }
}

class _NoteFacePainter extends CustomPainter {
  _NoteFacePainter(this.note);
  final ParkNote note;

  @override
  void paint(Canvas canvas, Size size) => NoteCard.paintFace(canvas, note.title, note.body, note.icon, dark: true);

  @override
  bool shouldRepaint(_NoteFacePainter old) => old.note != note;
}

/// The pool of light Lumi casts on the cards while it glides over them.
class _LightPoolPainter extends CustomPainter {
  _LightPoolPainter(this.brain) : super(repaint: brain.frame);
  final LumiBrain brain;

  @override
  void paint(Canvas canvas, Size size) {
    final k = brain.poolStrength;
    if (k <= 0.01) return;
    final c = brain.poolPos;
    const r = 150.0;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF9FD0FF).withValues(alpha: 0.42 * k),
            const Color(0xFF5E8CFF).withValues(alpha: 0.16 * k),
            const Color(0x005E8CFF),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant _LightPoolPainter old) => false;
}

class _FlyingKey extends StatefulWidget {
  const _FlyingKey({required this.from, required this.to, required this.onDone});
  final Offset from;
  final Offset Function() to;
  final VoidCallback onDone;
  @override
  State<_FlyingKey> createState() => _FlyingKeyState();
}

class _FlyingKeyState extends State<_FlyingKey> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (_, _) {
        final t = Curves.easeInOutCubic.transform(c.value);
        final to = widget.to();
        final p = Offset.lerp(widget.from, to, t)! + Offset(0, -math.sin(t * math.pi) * 120);
        final s = 1.0 + math.sin(t * math.pi) * 0.5 - t * 0.6;
        return Positioned(
          left: p.dx - 16,
          top: p.dy - 16,
          child: IgnorePointer(
            child: Transform.scale(
              scale: s,
              child: Transform.rotate(angle: t * 6.28, child: const KeyCoin(size: 32)),
            ),
          ),
        );
      },
    );
  }
}

class _PhotoFlash extends StatefulWidget {
  const _PhotoFlash({required this.brain, required this.onDone});
  final LumiBrain brain;
  final VoidCallback onDone;
  @override
  State<_PhotoFlash> createState() => _PhotoFlashState();
}

class _PhotoFlashState extends State<_PhotoFlash> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final t = c.value * 3.2;
        final flash = t < 0.35 ? (1 - t / 0.35) : 0.0;
        final card = ((t - 0.25) / 0.5).clamp(0.0, 1.0);
        final out = ((t - 2.6) / 0.5).clamp(0.0, 1.0);
        final size = MediaQuery.sizeOf(context);
        final name = widget.brain.rig?.style.name ?? 'Lumi';
        return IgnorePointer(
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Colors.white.withValues(alpha: flash * 0.9)),
              ),
              Positioned(
                left: size.width / 2 - 95,
                top: size.height * 0.36 + (1 - Curves.easeOutBack.transform(card)) * 60 + out * size.height,
                child: Opacity(
                  opacity: card,
                  child: Transform.rotate(
                    angle: -0.06,
                    child: Container(
                      width: 190,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 20)],
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 150,
                            child: ClipRect(
                              child: CustomPaint(
                                size: const Size(170, 150),
                                painter: _PolaroidPainter(widget.brain.friend),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Me & $name · Parkday',
                            style: Pd.t(11.5, w: FontWeight.w600, c: const Color(0xFF2A2F55)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PolaroidPainter extends CustomPainter {
  _PolaroidPainter(this.f);
  final Friend f;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = const Color(0xFF1B2152));
    final rnd = math.Random(2);
    for (var i = 0; i < 40; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        0.8,
        Paint()..color = Colors.white54,
      );
    }
    final p = FriendPortrait(f);
    canvas.save();
    canvas.translate(10, 4);
    canvas.scale(0.9);
    p.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
