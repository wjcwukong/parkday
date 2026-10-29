import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../theme.dart';
import 'space.dart';

/// A park notification as a card in the 3D scene, so Lumi can hold it, tip
/// it over and swallow it whole (the card ends up inside the glass head).
///
/// The card is painted once into a texture: the home scene is screen
/// blended onto the UI, which a live `WidgetComponent` (a composited layer)
/// would break, and a notification never changes once shown.
class NoteCard {
  NoteCard._(this.node, this.material);

  /// Card size in logical pixels; one world unit is 100 of them at home.
  static const size = Size(156, 50);

  final Node node;
  final UnlitMaterial material;

  set opacity(double v) => material.baseColorFactor = vm.Vector4(0.82, 0.82, 0.82, v.clamp(0, 1));

  static Future<NoteCard> create(String title, String body, IconData icon) async {
    const scale = 3.0;
    final image = await _paint(title, body, icon, scale);
    final texture = await Texture2D.fromImage(image);
    image.dispose();
    final material = UnlitMaterial(colorTexture: texture)
      ..alphaMode = AlphaMode.blend
      ..doubleSided = true;
    final card = NoteCard._(
      Node(name: 'note', mesh: Mesh(cardQuad(size.width / 100, size.height / 100), material)),
      material,
    );
    card.opacity = 0;
    return card;
  }

  static Future<ui.Image> _paint(String title, String body, IconData icon, double scale) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(scale);
    paintFace(c, title, body, icon);
    final picture = rec.endRecording();
    final image = await picture.toImage((size.width * scale).round(), (size.height * scale).round());
    picture.dispose();
    return image;
  }

  /// Paints the card's face into [c] at [size]. [dark] is the solid card
  /// shown in front of Lumi; the light one glows inside the glass head,
  /// where the scene is screen-blended and a dark card would vanish.
  static void paintFace(Canvas c, String title, String body, IconData icon, {bool dark = false}) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    c.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xF5191C38), Color(0xF50C0E22)]
              : const [Color(0xF2323A72), Color(0xF21E2350)],
        ).createShader(Offset.zero & size),
    );
    c.drawRRect(
      r.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = dark ? const Color(0x30FFFFFF) : const Color(0x40FFFFFF),
    );
    TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: 13, color: Pd.gold),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(c, const Offset(9, 9));
    TextPainter(
        text: TextSpan(
          text: title,
          style: Pd.t(10.5, w: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )
      ..layout(maxWidth: size.width - 38)
      ..paint(c, const Offset(28, 8));
    TextPainter(
        text: TextSpan(
          text: body,
          style: Pd.t(9, c: Pd.textDim, h: 1.25),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )
      ..layout(maxWidth: size.width - 38)
      ..paint(c, const Offset(28, 22));
  }
}
