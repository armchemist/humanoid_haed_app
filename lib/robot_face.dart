import 'dart:math' as math;
import 'package:flutter/material.dart';

enum RobotState { normal, caution, danger, sleep }

/// Drive the face from anywhere: `controller.setState(RobotState.danger)`.
class RobotFaceController extends ValueNotifier<RobotState> {
  RobotFaceController([super.initial = RobotState.normal]);
  void setState(RobotState s) => value = s;
}

class _FaceParams {
  const _FaceParams({
    required this.browAngle,
    required this.browLift,
    required this.eyeHeight,
    required this.eyeTilt,
    required this.mouthCurve,
    required this.drift,
    required this.breathe,
    required this.shake,
    required this.face,
  });
  final Color face;
  final double browAngle, browLift, eyeHeight, eyeTilt, mouthCurve;
  final double drift, breathe, shake; // motion weights 0..1

  static double _l(double a, double b, double t) => a + (b - a) * t;
  static _FaceParams lerp(_FaceParams a, _FaceParams b, double t) => _FaceParams(
        browAngle: _l(a.browAngle, b.browAngle, t),
        browLift: _l(a.browLift, b.browLift, t),
        eyeHeight: _l(a.eyeHeight, b.eyeHeight, t),
        eyeTilt: _l(a.eyeTilt, b.eyeTilt, t),
        mouthCurve: _l(a.mouthCurve, b.mouthCurve, t),
        drift: _l(a.drift, b.drift, t),
        breathe: _l(a.breathe, b.breathe, t),
        shake: _l(a.shake, b.shake, t),
        face: Color.lerp(a.face, b.face, t)!,
      );
}

const Map<RobotState, _FaceParams> _params = {
  RobotState.normal: _FaceParams(
      browAngle: -0.06, browLift: 0.15, eyeHeight: 1.0, eyeTilt: 0.0,
      mouthCurve: 1.0, drift: 1, breathe: 0, shake: 0, face: Color(0xFF5AAEFF)),
  RobotState.caution: _FaceParams(
      browAngle: 0.14, browLift: 0.0, eyeHeight: 0.5, eyeTilt: 0.0,
      mouthCurve: 0.0, drift: 0, breathe: 1, shake: 0, face: Color(0xFFFFC044)),
  RobotState.danger: _FaceParams(
      browAngle: 0.40, browLift: -0.12, eyeHeight: 0.9, eyeTilt: 0.22,
      mouthCurve: -1.0, drift: 0, breathe: 0, shake: 1, face: Color(0xFFFF4D42)),
  RobotState.sleep: _FaceParams(
      browAngle: -0.10, browLift: -0.15, eyeHeight: 0.08, eyeTilt: 0.0,
      mouthCurve: 0.25, drift: 0, breathe: 1, shake: 0, face: Color(0xFF9C8CFF)),
};

const _blue = Color(0xFF3D9BFF);
const _amber = Color(0xFFFFB020);
const _red = Color(0xFFFF3B30);
const _violet = Color(0xFF9C8CFF);

List<double> _oneHot(RobotState s) =>
    List.generate(RobotState.values.length, (i) => i == s.index ? 1.0 : 0.0);

class RobotFace extends StatefulWidget {
  const RobotFace({super.key, required this.controller});
  final RobotFaceController controller;

  @override
  State<RobotFace> createState() => _RobotFaceState();
}

class _RobotFaceState extends State<RobotFace> with TickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(hours: 1))..repeat();
  late final AnimationController _fade = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350), value: 1);

  late RobotState _target = widget.controller.value;
  late _FaceParams _from = _params[_target]!;
  late List<double> _fromIcons = _oneHot(_target);

  double get _k => Curves.easeInOut.transform(_fade.value);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onState);
  }

  @override
  void didUpdateWidget(RobotFace old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onState);
      widget.controller.addListener(_onState);
      _onState();
    }
  }

  void _onState() {
    final next = widget.controller.value;
    if (next == _target) return;
    // Snapshot the in-flight blend so interrupted transitions stay smooth.
    final k = _k;
    _from = _FaceParams.lerp(_from, _params[_target]!, k);
    final to = _oneHot(_target);
    _fromIcons = List.generate(RobotState.values.length, (i) => _fromIcons[i] + (to[i] - _fromIcons[i]) * k);
    _target = next;
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onState);
    _clock.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: Listenable.merge([_clock, _fade]),
        builder: (_, _) {
          final k = _k;
          final to = _oneHot(_target);
          return CustomPaint(
            painter: _RobotFacePainter(
              p: _FaceParams.lerp(_from, _params[_target]!, k),
              icons: List.generate(RobotState.values.length, (i) => _fromIcons[i] + (to[i] - _fromIcons[i]) * k),
              t: _clock.value * 3600,
            ),
          );
        },
      ),
    );
  }
}

class _RobotFacePainter extends CustomPainter {
  _RobotFacePainter({required this.p, required this.icons, required this.t});
  final _FaceParams p;
  final List<double> icons;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final s = math.min(size.width / 14, size.height / 8.5);
    final c = size.center(Offset.zero);

    // Motion
    final drift = Offset(math.sin(t * 0.7) * 0.22 + math.sin(t * 0.31) * 0.12,
            math.cos(t * 0.53) * 0.15) * s * p.drift;
    final breath = math.sin(t * 2 * math.pi / 3.5);
    final scale = 1 + 0.03 * breath * p.breathe;
    final q = t % 1.8;
    final env = q < 0.45 ? math.sin(q / 0.45 * math.pi) : 0.0;
    final shakeX = math.sin(t * 2 * math.pi * 9) * 0.14 * s * env * p.shake;

    final stroke = Paint()
      ..color = p.face
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.26 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = p.face;

    canvas.save();
    canvas.translate(c.dx + drift.dx + shakeX,
        c.dy + drift.dy - 0.08 * s * breath * p.breathe);
    canvas.scale(scale);

    // Blink every ~4s
    final b = t % 4.0;
    final blink = b > 3.84 ? math.sin((b - 3.84) / 0.16 * math.pi) : 0.0;

    const eyeW = 0.8, eyeH0 = 1.7, eyeX = 2.1, eyeY = -0.5, browHalf = 0.65;
    final h = eyeH0 * p.eyeHeight * (1 - 0.88 * blink);
    final ey = eyeY + (eyeH0 - h) / 2; // lid drops from the top

    for (final side in const [-1.0, 1.0]) {
      // Eye
      canvas.save();
      canvas.translate(side * eyeX * s, ey * s);
      canvas.rotate(-side * p.eyeTilt); // tops lean toward center
      final w = eyeW * s, hh = math.max(h * s, 0.12 * s);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: w, height: hh),
              Radius.circular(math.min(w, hh) / 2)),
          fill);
      canvas.restore();

      // Brow: positive angle = inner end lower
      final bx = side * eyeX * s;
      final by = (eyeY - eyeH0 / 2 - 0.75 - p.browLift) * s;
      final dx = math.cos(p.browAngle) * browHalf * s;
      final dy = math.sin(p.browAngle) * browHalf * s;
      canvas.drawLine(Offset(bx - dx, by + side * dy), Offset(bx + dx, by - side * dy), stroke);
    }

    // Mouth
    const my = 1.7, mw = 1.3;
    final mouth = Path()
      ..moveTo(-mw * s, my * s)
      ..quadraticBezierTo(0, (my + p.mouthCurve * 1.0) * s, mw * s, my * s);
    canvas.drawPath(mouth, stroke);
    canvas.restore();

    // Status icons (crossfaded)
    final ic = Offset(size.width - 1.1 * s, 1.1 * s);
    final r = 0.48 * s;
    if (icons[0] > 0.01) _check(canvas, ic, r, s, icons[0]);
    if (icons[1] > 0.01) _exclaim(canvas, ic, r, s, icons[1]);
    if (icons[2] > 0.01) {
      final pulse = 0.5 + 0.5 * math.cos(t * 2 * math.pi * 1.25);
      _warning(canvas, ic, r, s, icons[2] * (0.25 + 0.75 * pulse * pulse));
    }
    if (icons[3] > 0.01) {
      final f = (t % 2.4) / 2.4;
      _sleepZ(canvas, ic.translate(0, -f * r * 0.6), r, s, icons[3] * math.sin(f * math.pi));
    }
  }

  Paint _p(Color c, double a, double s) => Paint()
    ..color = c.withAlpha((a.clamp(0, 1) * 255).round())
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.13 * s
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _check(Canvas canvas, Offset c, double r, double s, double a) {
    final pt = _p(_blue, a, s);
    canvas.drawCircle(c, r, pt);
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * 0.45, c.dy + r * 0.02)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.36)
          ..lineTo(c.dx + r * 0.48, c.dy - r * 0.32),
        pt);
  }

  void _exclaim(Canvas canvas, Offset c, double r, double s, double a) {
    final pt = _p(_amber, a, s);
    canvas.drawCircle(c, r, pt);
    canvas.drawLine(Offset(c.dx, c.dy - r * 0.48), Offset(c.dx, c.dy + r * 0.12), pt);
    canvas.drawCircle(Offset(c.dx, c.dy + r * 0.5), 0.075 * s,
        Paint()..color = _amber.withAlpha((a * 255).round()));
  }

  void _warning(Canvas canvas, Offset c, double r, double s, double a) {
    final pt = _p(_red, a, s);
    canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r * 1.0)
          ..lineTo(c.dx + r * 1.12, c.dy + r * 0.88)
          ..lineTo(c.dx - r * 1.12, c.dy + r * 0.88)
          ..close(),
        pt);
    canvas.drawLine(Offset(c.dx, c.dy - r * 0.32), Offset(c.dx, c.dy + r * 0.22), pt);
    canvas.drawCircle(Offset(c.dx, c.dy + r * 0.56), 0.07 * s,
        Paint()..color = _red.withAlpha((a * 255).round()));
  }

  void _sleepZ(Canvas canvas, Offset c, double r, double s, double a) {
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * 0.5, c.dy - r * 0.5)
          ..lineTo(c.dx + r * 0.5, c.dy - r * 0.5)
          ..lineTo(c.dx - r * 0.5, c.dy + r * 0.5)
          ..lineTo(c.dx + r * 0.5, c.dy + r * 0.5),
        _p(_violet, a, s));
  }

  @override
  bool shouldRepaint(covariant _RobotFacePainter old) => true;
}
