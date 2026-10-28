import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

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
