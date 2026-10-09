import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Holds the strokes drawn on a [SignaturePad].
class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _canvasSize = Size.zero;

  List<List<Offset>> get strokes => _strokes;

  /// Too few points is a tap, not a signature.
  bool get isEmpty => _strokes.fold<int>(0, (n, s) => n + s.length) < 8;

  void _start(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) return _start(p);
    _strokes.last.add(p);
    notifyListeners();
  }

  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// Transparent PNG of the strokes (dark ink), sized to the pad × [scale].
  Future<Uint8List?> toPng({double scale = 1.6}) async {
    if (isEmpty || _canvasSize.isEmpty) return null;
    final w = (_canvasSize.width * scale).round();
    final h = (_canvasSize.height * scale).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.scale(scale);
    SignaturePainter.paintStrokes(canvas, _strokes, SignaturePainter.ink, 2.4);
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }
}

/// Finger / mouse / stylus signature box. Claims the pointer immediately so
/// a surrounding scroll view does not steal strokes.
class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.height = 170});

  final SignaturePadController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      controller._canvasSize = Size(c.maxWidth, height);
      return RawGestureDetector(
        gestures: {
          _ImmediatePanRecognizer: GestureRecognizerFactoryWithHandlers<_ImmediatePanRecognizer>(
            _ImmediatePanRecognizer.new,
            (r) => r
              ..onStart = ((d) => controller._start(_clamp(d.localPosition, c.maxWidth)))
              ..onUpdate = ((d) => controller._extend(_clamp(d.localPosition, c.maxWidth))),
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => CustomPaint(
                  painter: SignaturePainter(controller.strokes),
                  child: controller.strokes.isEmpty
                      ? const Center(
                          child: Text(
                            'Sign here',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Offset _clamp(Offset p, double width) =>
      Offset(p.dx.clamp(0, width), p.dy.clamp(0, height));
}

class SignaturePainter extends CustomPainter {
  SignaturePainter(this.strokes);

  static const ink = Color(0xFF0F2A4A);

  final List<List<Offset>> strokes;

  static void paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, width / 2, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length - 1; i++) {
        final mid = Offset((s[i].dx + s[i + 1].dx) / 2, (s[i].dy + s[i + 1].dy) / 2);
        path.quadraticBezierTo(s[i].dx, s[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(s.last.dx, s.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(16, size.height - 34), Offset(size.width - 16, size.height - 34), guide);
    paintStrokes(canvas, strokes, ink, 2.4);
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}

class _ImmediatePanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
