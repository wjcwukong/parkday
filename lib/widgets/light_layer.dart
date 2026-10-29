import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../scene/lumi_rig.dart';
import '../scene/space.dart';

/// Paints its child as light: the child is drawn into its own layer and
/// screen-blended onto what is underneath, so black adds nothing and bright
/// pixels (Lumi, its bloom) brighten the UI below them.
///
/// The child must paint straight onto the canvas (a [CustomPaint], which is
/// what `SceneView` uses); a child that pushes its own compositing layers is
/// painted normally instead.
class LightLayer extends SingleChildRenderObjectWidget {
  const LightLayer({super.key, this.blendMode = BlendMode.screen, super.child});

  final BlendMode blendMode;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderLightLayer(blendMode);

  @override
  void updateRenderObject(BuildContext context, RenderLightLayer renderObject) {
    renderObject.blendMode = blendMode;
  }
}

/// Render object for [LightLayer].
class RenderLightLayer extends RenderProxyBox {
  RenderLightLayer(this._blendMode);

  BlendMode _blendMode;
  set blendMode(BlendMode value) {
    if (value == _blendMode) return;
    _blendMode = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (child.needsCompositing) {
      context.paintChild(child, offset);
      return;
    }
    final canvas = context.canvas;
    canvas.saveLayer(offset & size, Paint()..blendMode = _blendMode);
    context.paintChild(child, offset);
    canvas.restore();
  }
}

/// Darkens the page right behind Lumi's head and body, under a
/// [LightLayer]. Screen blending lightens whatever is below, so over a
/// bright painted sky Lumi would wash out to a pale ghost; over this shade
/// it keeps its own colours, as it does over the dark home page, while its
/// glow still spills onto the sky around it.
class LumiShadePainter extends CustomPainter {
  LumiShadePainter(this.rig, this.space, Listenable repaint) : super(repaint: repaint);
  final LumiRig? Function() rig;
  final ScreenSpace? Function() space;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rig(), sp = space();
    if (r == null || sp == null || !r.root.visible) return;
    final scale = r.root.globalTransform.getMaxScaleOnAxis();
    for (final (node, radius) in [(r.head, r.style.headRadius), (r.body, r.style.bodyRadius)]) {
      final c = node.globalTransform.getTranslation();
      final at = sp.toScreen(c);
      final px = radius * scale * sp.scaleAt(c.z);
      if (px < 1) continue;
      canvas.drawCircle(
        at,
        px,
        Paint()
          ..shader = RadialGradient(
            colors: const [Color(0xF0000000), Color(0xF0000000), Color(0x00000000)],
            stops: const [0, 0.82, 1],
          ).createShader(Rect.fromCircle(center: at, radius: px)),
      );
    }
  }

  @override
  bool shouldRepaint(LumiShadePainter old) => false;
}
