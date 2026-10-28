import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/park_data.dart';
import '../lumi/lumi_brain.dart';
import '../theme.dart';
import '../widgets/painters.dart';

/// Callbacks from the feed back to the home screen.
class FeedActions {
  const FeedActions({
    required this.watchFireworks,
    required this.openMap,
    required this.playStarCatch,
    required this.playSkyLift,
    required this.photoBooth,
  });
  final VoidCallback watchFireworks;
  final VoidCallback openMap;
  final VoidCallback playStarCatch;
  final VoidCallback playSkyLift;
  final VoidCallback photoBooth;
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Pd.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pd.stroke),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 17, color: Pd.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: Pd.t(12.5, c: Pd.text),
              cursorColor: Pd.lumiBlue,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search rides, food, shows',
                hintStyle: Pd.t(12.5, c: Pd.textDim, w: FontWeight.w400),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: const Icon(Icons.close_rounded, size: 16, color: Pd.textDim),
            ),
        ],
      ),
    );
  }
}

class SearchResults extends StatelessWidget {
  const SearchResults({super.key, required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final items = <(String, String, String)>[
      for (final r in rides) (r.name, '${r.wait} min', 'RIDE'),
      for (final d in dining) (d.name, d.status, 'FOOD'),
      for (final s in shows) (s.name, s.status, 'SHOW'),
    ].where((e) => e.$1.toLowerCase().contains(q)).toList();
    return PdCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${items.length} RESULTS', style: Pd.eyebrow()),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Lumi couldn’t find that one.', style: Pd.t(12.5, c: Pd.textDim)),
            ),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x228C9BFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(it.$3, style: Pd.eyebrow(Pd.accent)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(it.$1, style: Pd.t(13))),
                  Text(it.$2, style: Pd.t(12.5, w: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class FireworksCard extends StatelessWidget {
  const FireworksCard({super.key, required this.t, required this.onWatch, required this.friendName});
  final Animation<double> t;
  final VoidCallback onWatch;
  final String friendName;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onWatch,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 146,
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: FireworksThumbPainter(t))),
              Positioned(
                left: 12,
                bottom: 12,
                right: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TONIGHT · 9:15 PM', style: Pd.eyebrow(const Color(0xFFFFC56B))),
                    const SizedBox(height: 3),
                    Text('Fireworks over the lagoon', style: Pd.t(15.5, w: FontWeight.w700, h: 1.15)),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 14,
                child: PillButton(
                  label: 'Watch with $friendName',
                  icon: Icons.play_arrow_rounded,
                  onTap: onWatch,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KeyCoin extends StatelessWidget {
  const KeyCoin({super.key, this.size = 30});
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFFFFE08A), Color(0xFFE9A92B), Color(0xFFB57A12)],
        ),
        boxShadow: [BoxShadow(color: Color(0x55FFC34D), blurRadius: 10)],
      ),
      child: Icon(Icons.key_rounded, size: size * 0.55, color: const Color(0xFF7A4E05)),
    );
  }
}

class RewardCard extends StatelessWidget {
  const RewardCard({super.key, required this.brain, required this.onCollect});
  final LumiBrain brain;
  final void Function(Offset from) onCollect;

  @override
  Widget build(BuildContext context) {
    final all = brain.keys >= 5;
    final name = brain.rig?.style.name ?? 'Lumi';
    return PdCard(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text('REWARD NEARBY', style: Pd.eyebrow()),
              const Spacer(),
              GestureDetector(
                onTap: brain.away || all ? null : brain.sendLumi,
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 11, color: Pd.accent),
                    const SizedBox(width: 3),
                    Text(
                      brain.away ? '$name is searching…' : 'Send $name',
                      style: Pd.t(10.5, w: FontWeight.w600, c: Pd.accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const KeyCoin(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lagoon Key', style: Pd.t(14, w: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      all ? 'All 5 keys found · Cat ears unlocked' : '${brain.keys} of 5 keys found',
                      style: Pd.t(10.5, c: Pd.textDim),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (ctx) {
                  return PillButton(
                    label: all ? 'Collected' : 'Collect',
                    onTap: all
                        ? null
                        : () {
                            final box = ctx.findRenderObject() as RenderBox;
                            onCollect(box.localToGlobal(box.size.center(Offset.zero)));
                          },
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key, required this.brain});
  final LumiBrain brain;

  @override
  Widget build(BuildContext context) {
    final w = brain.weather;
    final (icon, label) = switch (w) {
      Weather.clear => (Icons.nightlight_round, 'Clear skies · 18°'),
      Weather.rain => (Icons.water_drop_rounded, 'Light rain from 10 PM · 16°'),
      Weather.snow => (Icons.ac_unit_rounded, 'Snow flurries · -1°'),
    };
    return PdCard(
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WEATHER', style: Pd.eyebrow()),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, size: 18, color: w == Weather.clear ? Pd.gold : Pd.lumiBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: Pd.t(13.5, w: FontWeight.w500)),
              ),
              for (final (ww, ic) in [
                (Weather.clear, Icons.nightlight_round),
                (Weather.rain, Icons.water_drop_rounded),
                (Weather.snow, Icons.ac_unit_rounded),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => brain.setWeather(ww),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: w == ww ? const Color(0xFF6FB8FF) : const Color(0x14FFFFFF),
                      ),
                      child: Icon(ic, size: 14, color: w == ww ? const Color(0xFF10163A) : Pd.textDim),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class PhotoBoothCard extends StatelessWidget {
  const PhotoBoothCard({super.key, required this.onTap, required this.friendName});
  final VoidCallback onTap;
  final String friendName;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PdCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFFF8FB1), Color(0xFFFF6A8E)]),
              ),
              child: const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PHOTO BOOTH', style: Pd.eyebrow()),
                  const SizedBox(height: 2),
                  Text('Strike a pose with $friendName', style: Pd.t(13.5, w: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Pd.textDim),
          ],
        ),
      ),
    );
  }
}

class PlayCard extends StatelessWidget {
  const PlayCard({
    super.key,
    required this.t,
    required this.stars,
    required this.best,
    required this.onStarCatch,
    required this.onSkyLift,
    required this.friendName,
  });
  final Animation<double> t;
  final int stars;
  final int best;
  final VoidCallback onStarCatch;
  final VoidCallback onSkyLift;
  final String friendName;

  @override
  Widget build(BuildContext context) {
    Widget tile(String title, String sub, CustomPainter p, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 92,
                width: double.infinity,
                child: CustomPaint(painter: p),
              ),
            ),
            const SizedBox(height: 7),
            Text(title, style: Pd.t(12.5, w: FontWeight.w600)),
            const SizedBox(height: 1),
            Text(sub, style: Pd.t(10, c: Pd.textDim)),
          ],
        ),
      ),
    );
    return PdCard(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PLAY WITH ${friendName.toUpperCase()} · $stars STARS', style: Pd.eyebrow()),
          const SizedBox(height: 9),
          Row(
            children: [
              tile('Star Catch', '45 seconds', _StarCatchThumb(t), onStarCatch),
              const SizedBox(width: 10),
              tile(
                'Sky Lift',
                best > 0 ? 'Best $best m' : 'How high can $friendName go?',
                _SkyLiftThumb(t),
                onSkyLift,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StarCatchThumb extends CustomPainter {
  _StarCatchThumb(this.t) : super(repaint: t);
  final Animation<double> t;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2B1E5E), Color(0xFF5B3C9A), Color(0xFF241848)],
        ).createShader(r),
    );
    final time = t.value * 60;
    for (var i = 0; i < 3; i++) {
      final x = size.width * (0.3 + i * 0.25);
      final y = (time * 22 + i * 30) % (size.height * 0.7);
      _star(canvas, Offset(x, y), 5, const Color(0xFFFFE08A));
    }
    // little pink Juju on a lily pad
    final c = Offset(size.width * 0.36, size.height * 0.68);
    canvas.drawOval(
      Rect.fromCenter(center: c + const Offset(0, 16), width: 30, height: 7),
      Paint()..color = const Color(0xFF5ED38C),
    );
    canvas.drawCircle(c, 9, Paint()..color = const Color(0xFFFF8A80));
    canvas.drawCircle(c + const Offset(0, 11), 5, Paint()..color = const Color(0xFFFF8A80));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SkyLiftThumb extends CustomPainter {
  _SkyLiftThumb(this.t) : super(repaint: t);
  final Animation<double> t;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE9B7D9), Color(0xFFF5D3E5), Color(0xFFD9A8E0)],
        ).createShader(r),
    );
    final time = t.value * 60;
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < 4; i++) {
      final x = (i * 47 + time * 8) % (size.width + 60) - 30;
      final y = size.height * (0.2 + 0.22 * i) % size.height;
      for (var k = 0; k < 3; k++) {
        canvas.drawCircle(Offset(x + k * 12, y + (k == 1 ? -5 : 0)), 10, cloud);
      }
    }
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      8,
      Paint()..color = const Color(0xFF8FC8FF),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _star(Canvas canvas, Offset c, double r, Color col) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final rr = i.isEven ? r : r * 0.45;
    final p = c + Offset(math.cos(a), math.sin(a)) * rr;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  path.close();
  canvas.drawPath(path, Paint()..color = col);
  canvas.drawCircle(
    c,
    r * 1.6,
    Paint()
      ..color = col.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );
}

class ParkMapCard extends StatelessWidget {
  const ParkMapCard({super.key, required this.onOpen, required this.friendName});
  final VoidCallback onOpen;
  final String friendName;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 118,
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _MapThumb())),
              Positioned(
                left: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PARK MAP · LIVE WAITS', style: Pd.eyebrow(const Color(0xFFE6F2FF))),
                    const SizedBox(height: 2),
                    Text('Where to next, $friendName?', style: Pd.t(15, w: FontWeight.w700)),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 14,
                child: PillButton(label: 'Open map', icon: Icons.map_rounded, onTap: onOpen),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapThumb extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = const Color(0xFF4FA866));
    final rnd = math.Random(4);
    for (var i = 0; i < 26; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        4 + rnd.nextDouble() * 6,
        Paint()..color = const Color(0xFF3D8F55),
      );
    }
    final path = Paint()
      ..color = const Color(0xFFB79B83)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(size.width * 0.55, size.height * 0.8), radius: 70),
      3.4,
      2.2,
      false,
      path,
    );
    void umbrella(Offset c, double rad, Color a, Color b) {
      for (var k = 0; k < 12; k++) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: rad),
          k * math.pi / 6,
          math.pi / 6,
          true,
          Paint()..color = k.isEven ? a : b,
        );
      }
    }

    umbrella(Offset(size.width * 0.52, size.height * 0.42), 26, const Color(0xFFF46A7E), Colors.white);
    umbrella(Offset(size.width * 0.18, size.height * 0.3), 18, const Color(0xFF8E6AE8), Colors.white);
    umbrella(Offset(size.width * 0.84, size.height * 0.28), 16, const Color(0xFF6AA8F4), Colors.white);
    final chip = Paint()..color = const Color(0xFF20264D);
    for (final o in [const Offset(0.3, 0.12), const Offset(0.66, 0.16), const Offset(0.8, 0.55)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(o.dx * size.width, o.dy * size.height), width: 40, height: 14),
          const Radius.circular(4),
        ),
        chip,
      );
    }
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, const Color(0xFF0E1230).withValues(alpha: 0.85)],
          stops: const [0.3, 1],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class WaitTimesCard extends StatelessWidget {
  const WaitTimesCard({super.key, this.highlight});
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    return PdCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              Text('WAIT TIMES', style: Pd.eyebrow()),
              const Spacer(),
              Text('Updated just now', style: Pd.t(9.5, c: Pd.textFaint)),
            ],
          ),
          const SizedBox(height: 6),
          for (final r in rides)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: highlight == r.name ? const Color(0x22FFFFFF) : Colors.transparent,
                border: Border.all(color: highlight == r.name ? const Color(0xFFE8C77A) : Colors.transparent),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(r.name, style: Pd.t(12.5))),
                  Text('${r.wait} min', style: Pd.t(12.5, w: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class DiningCard extends StatelessWidget {
  const DiningCard({super.key});
  @override
  Widget build(BuildContext context) {
    return PdCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        children: [
          Row(children: [Text('DINING', style: Pd.eyebrow())]),
          const SizedBox(height: 6),
          for (final d in dining)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: Row(
                children: [
                  Expanded(child: Text(d.name, style: Pd.t(12.5))),
                  Text(
                    d.status,
                    style: Pd.t(12.5, w: FontWeight.w700, c: d.status == 'Open' ? Pd.text : Pd.textDim),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
