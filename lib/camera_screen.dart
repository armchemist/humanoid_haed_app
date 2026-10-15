import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'face_screen.dart';
import 'server_connection.dart';
import 'vision.dart';

/// 전면 카메라 프리뷰 + 얼굴 박스 + 영상 전송/추적 토글.
/// 얼굴을 탭하면 추적 대상으로 선택된다.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.server, required this.vision});
  final Server server;
  final Vision vision;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  @override
  void initState() {
    super.initState();
    widget.vision.previewOpen = true;
  }

  @override
  void dispose() {
    widget.vision.previewOpen = false; // 추적/전송 중이면 카메라는 계속 열려 있다
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.server, v = widget.vision;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: ListenableBuilder(
              listenable: Listenable.merge([v.camera, v.error]),
              builder: (context, _) {
                final c = v.camera.value;
                if (v.error.value != null) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(v.error.value!, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: v.sync, child: const Text('다시 시도')),
                    ]),
                  );
                }
                if (c == null || !c.value.isInitialized) return const CircularProgressIndicator();
                return CameraPreview(
                  c,
                  child: LayoutBuilder(
                    builder: (context, box) => GestureDetector(
                      onTapUp: (d) => v.selectAt(Offset(
                          d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight)),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([v.faces, v.selected]),
                        builder: (context, _) => CustomPaint(
                          size: Size.infinite,
                          painter: _BoxPainter(v.faces.value, v.selected.value),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: 4,
            top: 0,
            right: 4,
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              ConnectionBadge(server: s),
            ]),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 8,
            child: ListenableBuilder(
              listenable: Listenable.merge(
                  [s.videoOn, s.tracking, s.connected, v.stats, v.selected, v.faces]),
              builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${v.stats.value}\n얼굴 ${v.faces.value.length}개 · '
                  '${s.tracking.value ? '추적 대상 id=${v.selected.value ?? '없음 (얼굴을 탭)'}' : '추적 꺼짐'}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 3)]),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  FilterChip(
                    label: const Text('영상 전송'),
                    selected: s.videoOn.value,
                    onSelected: s.connected.value || s.videoOn.value
                        ? (on) => on ? s.startVideo() : s.stopVideo()
                        : null,
                  ),
                  FilterChip(
                    label: const Text('얼굴 추적'),
                    selected: s.tracking.value,
                    onSelected: (on) => s.tracking.value = on,
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.faces, this.selected);
  final List<FaceBox> faces;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in faces) {
      final sel = f.id != null && f.id == selected;
      final b = f.box;
      // 프리뷰는 거울처럼 좌우 반전되어 있으므로 x 를 뒤집어 그린다
      final rect = Rect.fromLTRB(
          (1 - b.right) * size.width, b.top * size.height, (1 - b.left) * size.width, b.bottom * size.height);
      canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 4 : 2
            ..color = sel ? Colors.greenAccent : Colors.white70);
      TextPainter(
        text: TextSpan(
            text: 'id ${f.id ?? '-'}',
            style: TextStyle(color: sel ? Colors.greenAccent : Colors.white70, fontSize: 14)),
        textDirection: TextDirection.ltr,
      )
        ..layout()
        ..paint(canvas, rect.topLeft + const Offset(4, 2));
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.faces != faces || old.selected != selected;
}
