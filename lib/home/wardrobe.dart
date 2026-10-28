import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../lumi/lumi_brain.dart';
import '../scene/lumi_rig.dart';
import '../theme.dart';

/// Friends, hats, colors and glow, in a panel that replaces the feed.
class WardrobePanel extends StatefulWidget {
  const WardrobePanel({super.key, required this.brain, required this.onClose});
  final LumiBrain brain;
  final VoidCallback onClose;

  @override
  State<WardrobePanel> createState() => _WardrobePanelState();
}

class _WardrobePanelState extends State<WardrobePanel> {
  int tab = 1;

  @override
  Widget build(BuildContext context) {
    final b = widget.brain;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF0151937),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: Pd.stroke)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Wardrobe', style: Pd.t(15, w: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('${b.keys} keys · ${b.stars} stars', style: Pd.t(10.5, c: Pd.textDim)),
              const Spacer(),
              GestureDetector(
                onTap: widget.onClose,
                child: const Icon(Icons.close_rounded, size: 20, color: Pd.text),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Row(
              children: [
                for (final (i, label) in const [(0, 'Friends'), (1, 'Hats'), (2, 'Colors'), (3, 'Glow')])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => tab = i),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tab == i ? const Color(0x33FFFFFF) : Colors.transparent,
                          border: i > 0 ? const Border(left: BorderSide(color: Color(0x33FFFFFF))) : null,
                        ),
                        child: Text(label, style: Pd.t(11.5, w: FontWeight.w600)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AnimatedBuilder(
              animation: b,
              builder: (context, _) => switch (tab) {
                0 => _friends(b),
                1 => _hats(b),
                2 => _colors(b),
                _ => _glow(b),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required bool selected,
    required Widget art,
    required String label,
    String? sub,
    bool locked = false,
    required VoidCallback onTap,
    double aspect = 0.92,
  }) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: AspectRatio(
        aspectRatio: aspect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2350),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF8FD3FF) : const Color(0x14FFFFFF),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected ? const [BoxShadow(color: Color(0x448FD3FF), blurRadius: 12)] : null,
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Opacity(opacity: locked ? 0.45 : 1, child: art),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Pd.t(10.5, w: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (sub != null) Text(sub, style: Pd.t(8.5, c: Pd.textDim)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(int cols, List<Widget> children) => GridView.count(
    padding: const EdgeInsets.only(bottom: 24),
    crossAxisCount: cols,
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    childAspectRatio: cols == 2 ? 1.05 : 0.92,
    children: children,
  );

  Widget _friends(LumiBrain b) => _grid(
    2,
    [
      for (final f in Friend.values)
        _tile(
          selected: b.friend == f,
          aspect: 1.05,
          art: SizedBox.expand(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(painter: FriendPortrait(f)),
            ),
          ),
          label: '',
          onTap: () => b.setFriend(f),
        ),
    ].indexed.map((e) {
      final f = Friend.values[e.$1];
      final s = FriendStyle.styles[f]!;
      return Stack(
        children: [
          e.$2,
          Positioned(
            left: 10,
            bottom: 9,
            child: Row(
              children: [
                Text(s.name, style: Pd.t(11, w: FontWeight.w700)),
                const SizedBox(width: 5),
                Text(s.tagline, style: Pd.eyebrow(Pd.textDim)),
              ],
            ),
          ),
        ],
      );
    }).toList(),
  );

  Widget _hats(LumiBrain b) => _grid(3, [
    for (final h in Hat.values)
      _tile(
        selected: b.hat == h,
        locked: h == Hat.catEars && b.keys < 5,
        art: CustomPaint(size: const Size(52, 52), painter: HatIcon(h)),
        label: _hatName(h),
        sub: h == Hat.catEars && b.keys < 5 ? 'Find 5 keys' : null,
        onTap: () => b.setHat(h),
      ),
  ]);

  Widget _colors(LumiBrain b) {
    const names = ['Original', 'Lavender', 'Seafoam', 'Rose', 'Honey'];
    return _grid(3, [
      for (var i = 0; i < LumiBrain.tints.length; i++)
        _tile(
          selected: b.colorIndex == i,
          art: _swatch(LumiBrain.tints[i] == null ? FriendStyle.styles[b.friend]!.tint : LumiBrain.tints[i]!),
          label: names[i],
          onTap: () => b.setColor(i),
        ),
    ]);
  }

  Widget _glow(LumiBrain b) {
    const names = ['Ember', 'Mint', 'Rose', 'Moonlight'];
    return _grid(3, [
      for (var i = 0; i < LumiBrain.glows.length; i++)
        _tile(
          selected: b.glowIndex == i,
          art: _orb(LumiBrain.glows[i] == null ? FriendStyle.styles[b.friend]!.orb : LumiBrain.glows[i]!),
          label: names[i],
          onTap: () => b.setGlow(i),
        ),
    ]);
  }

  Widget _swatch(vm.Vector3 c) {
    final col = displayColor(c);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(col, Colors.white, 0.5)!, col, Color.lerp(col, Colors.black, 0.3)!],
        ),
        boxShadow: [BoxShadow(color: col.withValues(alpha: 0.5), blurRadius: 14)],
      ),
    );
  }

  Widget _orb(vm.Vector3 c) {
    final col = displayColor(c, normalize: true);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(col, Colors.white, 0.35),
        boxShadow: [BoxShadow(color: col, blurRadius: 18, spreadRadius: 4)],
      ),
    );
  }

  static String _hatName(Hat h) => switch (h) {
    Hat.none => 'None',
    Hat.starSprout => 'Star sprout',
    Hat.beanie => 'Beanie',
    Hat.flowerCrown => 'Flower crown',
    Hat.headphones => 'Headphones',
    Hat.catEars => 'Cat ears',
  };
}

/// A small painted portrait of each friend for the wardrobe grid.
class FriendPortrait extends CustomPainter {
  FriendPortrait(this.f);
  final Friend f;

  @override
  void paint(Canvas canvas, Size size) {
    final s = FriendStyle.styles[f]!;
    final tint = displayColor(s.tint);
    final bgs = {
      Friend.lumi: [const Color(0xFF283070), const Color(0xFF151A40)],
      Friend.juju: [const Color(0xFFFFD9A8), const Color(0xFFF6B48A)],
      Friend.mochi: [const Color(0xFFD7F2C8), const Color(0xFFA9DDA0)],
      Friend.nova: [const Color(0xFF4A3A9A), const Color(0xFF231A55)],
    }[f]!;
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: bgs,
        ).createShader(r),
    );
    final cx = size.width / 2;
    final hr = size.height * 0.24 * s.headRadius / 0.56;
    final head = Offset(cx, size.height * 0.36);
    canvas.drawCircle(
      head,
      hr * 1.7,
      Paint()
        ..shader = RadialGradient(colors: [tint.withValues(alpha: 0.35), tint.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: head, radius: hr * 1.7)),
    );
    final body = head + Offset(0, hr + size.height * 0.1);
    canvas.drawCircle(
      body,
      hr * s.bodyRadius / s.headRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(tint, Colors.white, 0.45)!, tint],
        ).createShader(Rect.fromCircle(center: body, radius: hr * 0.6)),
    );
    canvas.drawCircle(
      head,
      hr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(tint, Colors.white, 0.55)!, tint, Color.lerp(tint, Colors.black, 0.15)!],
          stops: const [0, 0.7, 1],
        ).createShader(Rect.fromCircle(center: head, radius: hr)),
    );
    final eye = Paint()..color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(center: head + Offset(-hr * 0.3, 0), width: hr * 0.22, height: hr * 0.3),
      eye,
    );
    canvas.drawOval(
      Rect.fromCenter(center: head + Offset(hr * 0.3, 0), width: hr * 0.22, height: hr * 0.3),
      eye,
    );
    final orb = displayColor(s.orb, normalize: true);
    for (final o in [Offset(-hr * 1.15, hr * 0.95), Offset(hr * 1.15, hr * 0.95)]) {
      canvas.drawCircle(head + o, hr * 0.17, Paint()..color = Color.lerp(orb, Colors.white, 0.4)!);
    }
    if (f == Friend.nova) {
      canvas.drawOval(
        Rect.fromCenter(center: head, width: hr * 3, height: hr * 0.8),
        Paint()
          ..color = const Color(0xFFCBB6FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FriendPortrait old) => old.f != f;
}

/// Icon art for each hat: a small Lumi head wearing it.
class HatIcon extends CustomPainter {
  HatIcon(this.h);
  final Hat h;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.62);
    final r = size.width * 0.3;
    if (h == Hat.none) {
      final p = Paint()
        ..color = Pd.textDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 9, p);
      canvas.drawLine(
        Offset(size.width / 2 - 6, size.height / 2 + 6),
        Offset(size.width / 2 + 6, size.height / 2 - 6),
        p,
      );
      return;
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFFBFE0FF), Color(0xFF5E9BFF)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final eye = Paint()..color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(-r * 0.32, r * 0.05), width: r * 0.22, height: r * 0.3),
      eye,
    );
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(r * 0.32, r * 0.05), width: r * 0.22, height: r * 0.3),
      eye,
    );
    final top = c - Offset(0, r);
    switch (h) {
      case Hat.starSprout:
        canvas.drawLine(
          top,
          top - Offset(0, r * 0.6),
          Paint()
            ..color = const Color(0xFF8BE39C)
            ..strokeWidth = 1.6,
        );
        _starPath(canvas, top - Offset(0, r * 0.75), r * 0.32, const Color(0xFFFFE08A));
      case Hat.beanie:
        canvas.drawArc(
          Rect.fromCircle(center: c - Offset(0, r * 0.15), radius: r * 1.02),
          math.pi,
          math.pi,
          true,
          Paint()..color = const Color(0xFFFF7FA0),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c - Offset(0, r * 0.18), width: r * 2.1, height: r * 0.32),
            const Radius.circular(4),
          ),
          Paint()..color = const Color(0xFFFFF0E6),
        );
        canvas.drawCircle(top - Offset(0, r * 0.25), r * 0.2, Paint()..color = const Color(0xFFFFEAF0));
      case Hat.flowerCrown:
        for (var i = 0; i < 5; i++) {
          final x = -r * 0.8 + i * r * 0.4;
          canvas.drawCircle(
            c + Offset(x, -r * 0.85 + (i - 2).abs() * r * 0.08),
            r * 0.17,
            Paint()
              ..color = [const Color(0xFFFF9BB5), const Color(0xFFFFE08A), const Color(0xFFB8A6FF)][i % 3],
          );
        }
      case Hat.headphones:
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 1.12),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = const Color(0xFFDDE6FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        for (final s in [-1.0, 1.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: c + Offset(s * r * 1.1, 0), width: r * 0.42, height: r * 0.75),
              const Radius.circular(5),
            ),
            Paint()..color = const Color(0xFFDDE6FF),
          );
        }
      case Hat.catEars:
        for (final s in [-1.0, 1.0]) {
          final p = Path()
            ..moveTo(c.dx + s * r * 0.2, top.dy + r * 0.2)
            ..lineTo(c.dx + s * r * 0.55, top.dy - r * 0.5)
            ..lineTo(c.dx + s * r * 0.85, top.dy + r * 0.45)
            ..close();
          canvas.drawPath(p, Paint()..color = const Color(0xFFD38CFF));
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c + Offset(0, -r * 0.2), width: 14, height: 12),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xCC2A2F5E),
        );
      case Hat.none:
        break;
    }
  }

  void _starPath(Canvas canvas, Offset c, double r, Color col) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.45;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = col);
  }

  @override
  bool shouldRepaint(covariant HatIcon old) => old.h != h;
}
