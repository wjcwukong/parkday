import 'package:flutter/material.dart';

/// Parkday's night palette.
abstract final class Pd {
  static const bgTop = Color(0xFF1B2152);
  static const bg = Color(0xFF121638);
  static const bgDeep = Color(0xFF0A0D26);
  static const card = Color(0xFF1C2147);
  static const cardHi = Color(0xFF242A57);
  static const stroke = Color(0x1FFFFFFF);
  static const text = Color(0xFFF4F5FF);
  static const textDim = Color(0xFFA9AED6);
  static const textFaint = Color(0xFF7A80AE);
  static const accent = Color(0xFF8C9BFF);
  static const lumiBlue = Color(0xFF6FB8FF);
  static const coral = Color(0xFFFF7A5C);
  static const mint = Color(0xFF9DF2D6);
  static const gold = Color(0xFFFFC34D);
  static const amber = Color(0xFFFFB347);
  static const purple = Color(0xFF6B3FA0);

  static const font = 'Inter';

  static TextStyle t(double size, {FontWeight w = FontWeight.w500, Color c = text, double? ls, double? h}) =>
      TextStyle(fontFamily: font, fontSize: size, fontWeight: w, color: c, letterSpacing: ls, height: h);

  /// Small caps label used above cards ("REWARD NEARBY").
  static TextStyle eyebrow([Color c = textFaint]) => t(9.5, w: FontWeight.w700, c: c, ls: 1.1);

  static ThemeData theme() => ThemeData(
    brightness: Brightness.dark,
    fontFamily: font,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(primary: accent, surface: card),
    splashFactory: InkSparkle.splashFactory,
  );
}

/// A rounded dark card with the hairline border used across the home feed.
class PdCard extends StatelessWidget {
  const PdCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.highlight = false,
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Pd.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? const Color(0xFFE8C77A) : Pd.stroke,
          width: highlight ? 1.4 : 1,
        ),
        boxShadow: highlight ? const [BoxShadow(color: Color(0x55E8C77A), blurRadius: 18)] : null,
      ),
      child: child,
    );
  }
}

/// White pill button ("Collect", "Watch with Lumi").
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, this.icon, required this.onTap});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: const Color(0xFF14183A)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: Pd.t(11.5, w: FontWeight.w600, c: const Color(0xFF14183A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round translucent icon button used in the greeting row.
class RoundIcon extends StatelessWidget {
  const RoundIcon({super.key, required this.icon, required this.onTap, this.active = false, this.size = 34});
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? const Color(0x55FFFFFF) : const Color(0x26FFFFFF),
          border: Border.all(color: active ? Colors.white70 : const Color(0x14FFFFFF)),
          boxShadow: active ? const [BoxShadow(color: Color(0x668CB4FF), blurRadius: 14)] : null,
        ),
        child: Icon(icon, size: size * 0.5, color: Colors.white),
      ),
    );
  }
}
