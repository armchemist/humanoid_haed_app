import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'camera_screen.dart';
import 'robot_face.dart';
import 'server_connection.dart';
import 'vision.dart';

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
  final _face = RobotFaceController();
  late final _state = Listenable.merge([widget.server.expression, widget.server.connected, widget.server.status]);

  @override
  void initState() {
    super.initState();
    _syncFace();
    _state.addListener(_syncFace);
  }

  void _syncFace() => _face.setState(robotState(widget.server));

  @override
  void dispose() {
    _state.removeListener(_syncFace);
    _face.dispose();
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
            behavior: HitTestBehavior.opaque,
            onLongPress: _openTestPanel,
            // 디버그 빌드에서만: 탭하면 normal → caution → danger → sleep 순환
            onTap: kDebugMode
                ? () => _face.setState(RobotState.values[(_face.value.index + 1) % RobotState.values.length])
                : null,
            child: RobotFace(controller: _face),
          ),
        ),
        // 오른쪽 위는 얼굴의 상태 아이콘 자리라 버튼은 왼쪽 위 연결 표시 옆에 둔다.
        Positioned(
          left: 12,
          top: 0,
          child: SafeArea(
            child: Row(children: [
              ConnectionBadge(server: s),
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
                  style: const TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.w500),
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

/// 서버 표정 6종을 얼굴 상태 4종으로 묶는다. sleep 은 아직 서버에서 오지 않는다.
RobotState robotState(Server s) => switch (displayedState(s)) {
      'danger' => RobotState.danger,
      'error' => RobotState.caution,
      _ => RobotState.normal, // idle, thinking, working, done
    };

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
