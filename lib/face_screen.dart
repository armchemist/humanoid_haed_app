import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'camera_screen.dart';
import 'server_connection.dart';
import 'vision.dart';

const _colors = {
  'idle': Color(0xFF4DD0E1),
  'thinking': Color(0xFFFFC107),
  'working': Color(0xFF42A5F5),
  'danger': Color(0xFFFF3D3D),
  'done': Color(0xFF66BB6A),
  'error': Color(0xFFB388FF),
};

/// 로봇 얼굴. 화면 대부분을 얼굴이 차지하고, 연결 상태와 버튼은 구석에 작게 둔다.
/// 얼굴을 길게 누르면 수동 테스트 패널이 열린다.
class FaceScreen extends StatefulWidget {
  const FaceScreen({super.key, required this.server, required this.vision});
  final Server server;
  final Vision vision;

  @override
  State<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends State<FaceScreen> {
  final _rand = Random();
  Timer? _blinkTimer;
  bool _blink = false;

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 2500 + _rand.nextInt(3000)), () {
      if (!mounted) return;
      setState(() => _blink = true);
      _blinkTimer = Timer(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        setState(() => _blink = false);
        _scheduleBlink();
      });
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.server;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onLongPress: _openTestPanel,
            child: ListenableBuilder(
              listenable: Listenable.merge([s.expression, s.connected, s.status, widget.vision.target]),
              builder: (context, _) {
                final expr = displayedState(s);
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: CustomPaint(
                    key: ValueKey(expr),
                    size: Size.infinite,
                    painter: FacePainter(expr, blink: _blink, look: widget.vision.target.value),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 8,
          child: SafeArea(child: ConnectionBadge(server: s)),
        ),
        // 눈이 중심. 아래에 작은 상태 문구만 둔다.
        Positioned(
          left: 24,
          right: 24,
          bottom: 28,
          child: SafeArea(
            child: ListenableBuilder(
              listenable: Listenable.merge([s.expression, s.message, s.connected, s.status, s.videoOn]),
              builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  displayedMessage(s),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: (_colors[displayedState(s)] ?? _colors['idle']!).withValues(alpha: 0.85),
                      fontSize: 20,
                      fontWeight: FontWeight.w500),
                ),
                if (s.videoOn.value)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('● 카메라 전송 중', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
              ]),
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 0,
          child: SafeArea(
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.videocam, color: Colors.white38),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CameraScreen(server: s, vision: widget.vision))),
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white38),
                onPressed: () => showSettings(context, s),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  void _openTestPanel() {
    final s = widget.server;
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in expressions)
            ActionChip(label: Text(e), onPressed: () => s.expression.value = e),
          ValueListenableBuilder(
            valueListenable: s.tracking,
            builder: (_, on, _) => FilterChip(
              label: const Text('얼굴 추적'),
              selected: on,
              onSelected: (v) => s.tracking.value = v,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: s.videoOn,
            builder: (_, on, _) => FilterChip(
              label: const Text('영상 전송'),
              selected: on,
              onSelected: (v) => v ? s.startVideo() : s.stopVideo(),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 화면에 그릴 상태. 서버와 끊겨 있으면 서버가 보낸 상태를 유지하지 않고 error 를 보인다.
String displayedState(Server s) {
  if (s.connected.value) return s.expression.value;
  return s.status.value.startsWith('연결 중') ? 'idle' : 'error';
}

String displayedMessage(Server s) {
  if (!s.connected.value) {
    return s.status.value.startsWith('연결 중') ? '서버에 연결하고 있어요' : '서버 연결이 끊어졌어요';
  }
  final m = s.message.value;
  return m.isNotEmpty ? m : (defaultMessages[s.expression.value] ?? '');
}

/// 연결 상태 점 + 짧은 문구. 끊겼을 때 누르면 재연결.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.server});
  final Server server;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([server.connected, server.status]),
      builder: (context, _) {
        final ok = server.connected.value;
        return GestureDetector(
          onTap: ok ? null : server.reconnect,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 10, color: ok ? Colors.greenAccent : Colors.redAccent),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(server.status.value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            if (!ok) const Icon(Icons.refresh, size: 16, color: Colors.white54),
          ]),
        );
      },
    );
  }
}

Future<void> showSettings(BuildContext context, Server s) async {
  final url = TextEditingController(text: s.baseUrl);
  final id = TextEditingController(text: s.deviceId);
  final key = TextEditingController(text: s.apiKey);
  final fps = TextEditingController(text: '${s.videoFps}');
  final side = TextEditingController(text: '${s.videoMaxSide}');
  final quality = TextEditingController(text: '${s.videoQuality}');
  var highRes = s.videoHighRes, auto = s.autoVideo;
  final save = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('서버 설정'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: '서버 주소', hintText: 'http://100.x.x.x:8100'),
          ),
          TextField(controller: id, decoration: const InputDecoration(labelText: 'device_id')),
          TextField(
            controller: key,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API 키 (없으면 비움)'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: fps, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '영상 FPS'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: side, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '긴 변 px'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: quality, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'JPEG 품질'))),
          ]),
          StatefulBuilder(
            builder: (context, setState) => Column(children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('카메라 고해상도 (1280x720)'),
                subtitle: const Text('마커가 작게 보일 때. 다음에 카메라를 열 때 적용'),
                value: highRes,
                onChanged: (v) => setState(() => highRes = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('연결되면 영상 전송 자동 시작'),
                value: auto,
                onChanged: (v) => setState(() => auto = v),
              ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장 후 연결')),
      ],
    ),
  );
  if (save == true) {
    await s.saveSettings(url.text, id.text, key.text,
        fps: int.tryParse(fps.text), maxSide: int.tryParse(side.text),
        quality: int.tryParse(quality.text), highRes: highRes, auto: auto);
  }
}

/// 표정 하나를 그린다. 좌표는 모두 화면 크기에 대한 비율이라 세로/가로 모두 맞는다.
class FacePainter extends CustomPainter {
  FacePainter(this.expr, {this.blink = false, this.look});
  final String expr;
  final bool blink;

  /// 추적 중인 얼굴의 화면상 중심(0~1). 있으면 눈이 그쪽을 본다.
  final Offset? look;

  @override
  void paint(Canvas canvas, Size size) {
    final color = _colors[expr] ?? _colors['idle']!;
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width, h = size.height;
    final landscape = w > h;
    // 눈 크기 기준. 가로 화면에서는 아래 상태 문구와 입이 겹치지 않게 조금 작게, 위로.
    final r = landscape ? h * 0.14 : min(w, h) * 0.16;
    stroke.strokeWidth = r * 0.28;

    // 시선: 추적 대상 쪽으로 최대 r*0.5 만큼 이동
    var gaze = Offset.zero;
    if (look != null) gaze = Offset((look!.dx - 0.5) * r, (look!.dy - 0.5) * r);
    if (expr == 'thinking') gaze = Offset(r * 0.4, -r * 0.5);

    final eyeY = landscape ? h * 0.37 : h * 0.42;
    final eyes = [Offset(w * 0.5 - r * 1.9, eyeY) + gaze, Offset(w * 0.5 + r * 1.9, eyeY) + gaze];
    final mouth = Offset(w * 0.5, eyeY + r * 2.1) + gaze * 0.3;

    if (expr == 'danger') canvas.drawColor(const Color(0x33FF0000), BlendMode.srcOver);

    for (var i = 0; i < 2; i++) {
      final c = eyes[i];
      switch (expr) {
        case 'done': // ^ ^
          canvas.drawPath(
              Path()
                ..moveTo(c.dx - r * 0.8, c.dy + r * 0.3)
                ..quadraticBezierTo(c.dx, c.dy - r * 1.1, c.dx + r * 0.8, c.dy + r * 0.3),
              stroke);
        case 'error': // X X
          final d = r * 0.6;
          canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), stroke);
          canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), stroke);
        case 'danger': // 크게 뜬 동그란 눈
          canvas.drawCircle(c, r * (blink ? 0.2 : 1.0), fill);
        default:
          var eh = r * 2.0;
          if (expr == 'working') eh = r * 1.0;
          if (expr == 'thinking' && i == 0) eh = r * 1.3;
          if (blink) eh = r * 0.15;
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: c, width: r * 1.4, height: eh), Radius.circular(r * 0.5)),
              fill);
      }
    }

    // 눈썹: 집중할 때 안쪽으로 내려간다
    if (expr == 'working') {
      for (final sgn in [-1, 1]) {
        final c = eyes[sgn < 0 ? 0 : 1];
        canvas.drawLine(c + Offset(-sgn * r * 0.9, -r * 1.0), c + Offset(sgn * r * 0.6, -r * 0.6), stroke);
      }
    }

    // 입
    final mw = r * 1.6;
    switch (expr) {
      case 'done':
        canvas.drawArc(Rect.fromCenter(center: mouth, width: mw * 2, height: r * 1.6), 0.15, pi - 0.3, false, stroke);
      case 'error':
        canvas.drawArc(Rect.fromCenter(center: mouth + Offset(0, r * 0.6), width: mw * 1.6, height: r * 1.2),
            pi + 0.3, pi - 0.6, false, stroke);
      case 'danger':
        canvas.drawOval(Rect.fromCenter(center: mouth, width: r * 0.9, height: r * 1.2), stroke);
      case 'thinking':
        canvas.drawLine(mouth + Offset(-mw * 0.2, 0), mouth + Offset(mw * 0.5, -r * 0.2), stroke);
      case 'working':
        canvas.drawLine(mouth + Offset(-mw * 0.4, 0), mouth + Offset(mw * 0.4, 0), stroke);
      default: // idle: 살짝 웃는 입
        canvas.drawArc(Rect.fromCenter(center: mouth, width: mw, height: r * 0.6), 0.3, pi - 0.6, false, stroke);
    }
  }

  @override
  bool shouldRepaint(FacePainter old) => old.expr != expr || old.blink != blink || old.look != look;
}
