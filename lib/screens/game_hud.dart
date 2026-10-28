import 'package:flutter/material.dart';

import '../theme.dart';

/// Top bar shared by the mini games: close, a score readout, a timer or
/// altitude, a meter pill and a pause button.
class GameHud extends StatelessWidget {
  const GameHud({
    super.key,
    required this.left,
    required this.center,
    required this.meter,
    required this.paused,
    required this.onPause,
  });
  final Widget left;
  final Widget center;
  final double meter;
  final bool paused;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    Widget chip(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0x33101030), borderRadius: BorderRadius.circular(20)),
      child: child,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(6, pad.top + 8, 12, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
            chip(left),
            const Spacer(),
            chip(center),
            const SizedBox(width: 8),
            Container(
              width: 34,
              height: 12,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: const Color(0x33101030),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: meter.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC56B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onPause,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x44FFFFFF)),
                child: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GameCountdown extends StatelessWidget {
  const GameCountdown({super.key, required this.value, required this.hint});
  final double value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final n = value.ceil().clamp(1, 3);
    final f = value - value.floor();
    final show = value > 0.4;
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (show)
              Transform.scale(
                scale: 0.8 + f * 0.5,
                child: Text(
                  '$n',
                  style: Pd.t(
                    84,
                    w: FontWeight.w800,
                    c: Colors.white,
                  ).copyWith(shadows: const [Shadow(color: Color(0x88000000), blurRadius: 20)]),
                ),
              )
            else
              Text('Go!', style: Pd.t(52, w: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              hint,
              style: Pd.t(
                13,
                w: FontWeight.w600,
              ).copyWith(shadows: const [Shadow(color: Color(0x88000000), blurRadius: 10)]),
            ),
          ],
        ),
      ),
    );
  }
}

class GameOverCard extends StatelessWidget {
  const GameOverCard({
    super.key,
    required this.title,
    required this.lines,
    required this.onAgain,
    required this.onDone,
  });
  final String title;
  final List<String> lines;
  final VoidCallback onAgain;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x66000000),
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: BoxDecoration(
              color: const Color(0xF01C2147),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Pd.stroke),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Pd.t(24, w: FontWeight.w800)),
                const SizedBox(height: 10),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(l, style: Pd.t(13, c: Pd.textDim)),
                  ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: onDone,
                      child: Text('Done', style: Pd.t(13, w: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    PillButton(label: 'Play again', icon: Icons.replay_rounded, onTap: onAgain),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GamePausedCard extends StatelessWidget {
  const GamePausedCard({super.key, required this.onResume, required this.onQuit});
  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x55000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Paused', style: Pd.t(26, w: FontWeight.w800)),
              const SizedBox(height: 14),
              PillButton(label: 'Resume', icon: Icons.play_arrow_rounded, onTap: onResume),
              const SizedBox(height: 6),
              TextButton(
                onPressed: onQuit,
                child: Text('Quit', style: Pd.t(13, c: Pd.textDim)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
