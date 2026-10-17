import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'server_connection.dart';

/// 얼굴 하나. box 는 0~1 정규화 좌표이고, 서버로 보내는 JPEG 과 같은 기준이다
/// (세로/가로 회전 보정됨, 좌우 미러 아님). 화면에 그릴 때만 미러링한다.
typedef FaceBox = ({int? id, Rect box});

const _detectIntervalMs = 150; // 얼굴 검출 최대 ~6 FPS
// 영상 전송 FPS·크기·품질은 Server 의 설정(videoFps, videoMaxSide, videoQuality)을 쓴다.

/// 전면 카메라 하나를 열어 두고, 같은 프레임 스트림으로 얼굴 검출과 영상 전송을 한다.
/// 카메라는 필요할 때만 연다: 카메라 화면이 열렸거나, 추적 중이거나, 영상 전송 중.
class Vision {
  Vision(this.server) {
    Listenable.merge([server.tracking, server.videoOn]).addListener(sync);
    server.tracking.addListener(() {
      if (!server.tracking.value) {
        selected.value = null;
        target.value = null;
      }
    });
  }

  final Server server;
  final camera = ValueNotifier<CameraController?>(null);
  final error = ValueNotifier<String?>(null);
  final faces = ValueNotifier<List<FaceBox>>(const []);
  final selected = ValueNotifier<int?>(null); // 추적 대상 trackingId
  final target = ValueNotifier<Offset?>(null); // 얼굴 화면 시선용 (미러된 화면 좌표)
  final stats = ValueNotifier('');

  bool _previewOpen = false;
  bool _paused = false;

  final _detector = FaceDetector(
      options: FaceDetectorOptions(enableTracking: true, performanceMode: FaceDetectorMode.fast));
  static const _jpeg = MethodChannel('armchemist/jpeg');

  bool _detecting = false, _encoding = false;
  var _lastDetect = DateTime(0), _lastSend = DateTime(0), _statsAt = DateTime.now();
  int _detected = 0, _sent = 0;
  Future<void> _op = Future.value();

  bool get _needed =>
      !_paused && (_previewOpen || server.tracking.value || server.videoOn.value);

  set previewOpen(bool v) {
    _previewOpen = v;
    sync();
  }

  /// 백그라운드로 가면 영상 전송을 끊고 카메라를 닫는다.
  set paused(bool v) {
    _paused = v;
    if (v) server.stopVideo();
    sync();
  }

  /// 카메라가 필요한지 다시 판단해 열거나 닫는다. 열기/닫기가 겹치지 않게 순서대로 실행한다.
  Future<void> sync() => _op = _op.then((_) => _needed ? _open() : _close());

  Future<void> _open() async {
    if (camera.value != null) return;
    CameraController? c;
    try {
      final front = (await availableCameras()).where((d) => d.lensDirection == CameraLensDirection.front);
      if (front.isEmpty) throw '전면 카메라를 찾을 수 없습니다';
      // 권한 요청은 initialize() 안에서 플러그인이 한다.
      // 20mm ArUco 마커를 멀리서 읽어야 하면 설정에서 고해상도를 켠다.
      c = CameraController(front.first, server.videoHighRes ? ResolutionPreset.high : ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await c.initialize();
      await c.startImageStream(_onFrame);
      error.value = null;
      camera.value = c;
      server.cameraOn.value = true;
    } on CameraException catch (e) {
      await c?.dispose();
      error.value = e.code.contains('Access')
          ? '카메라 권한이 거부되었습니다. 설정 > 앱 > 권한에서 카메라를 허용하세요.'
          : '카메라 오류: ${e.code} ${e.description ?? ''}';
    } catch (e) {
      await c?.dispose();
      error.value = '$e';
    }
    if (camera.value == null) server.stopVideo(); // 카메라 없이 빈 영상 소켓을 열어두지 않는다
  }

  Future<void> _close() async {
    final c = camera.value;
    if (c == null) return;
    camera.value = null;
    server.cameraOn.value = false;
    faces.value = const [];
    target.value = null;
    try {
      await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  Future<void> dispose() async {
    _paused = true;
    await sync();
    await _detector.close();
  }

  void _onFrame(CameraImage img) {
    final c = camera.value;
    if (c == null) return;
    final now = DateTime.now();
    // 전면 카메라: 센서 방향 + 기기 방향 = 이미지를 똑바로 세우는 회전각 (ML Kit 예제와 동일)
    const deg = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final rot = (c.description.sensorOrientation + deg[c.value.deviceOrientation]!) % 360;
    // camera_android_camerax 는 nv21 요청 시 패딩 없는 NV21 을 plane 하나로 준다.
    final nv21 = img.planes.first.bytes;

    // 처리 중이면 이번 프레임은 버린다 (쌓지 않음).
    if ((_previewOpen || server.tracking.value) &&
        !_detecting &&
        now.difference(_lastDetect).inMilliseconds >= _detectIntervalMs) {
      _detecting = true;
      _lastDetect = now;
      _detect(nv21, img.width, img.height, rot).whenComplete(() => _detecting = false);
    }
    if (server.videoOn.value &&
        !_encoding &&
        now.difference(_lastSend).inMilliseconds >= 1000 ~/ server.videoFps) {
      _encoding = true;
      _lastSend = now;
      _encodeAndSend(nv21, img.width, img.height, rot).whenComplete(() => _encoding = false);
    }

    final dt = now.difference(_statsAt).inMilliseconds;
    if (dt >= 1000) {
      stats.value = '검출 ${(_detected * 1000 / dt).toStringAsFixed(1)} fps · '
          '전송 ${(_sent * 1000 / dt).toStringAsFixed(1)} fps · ${img.width}x${img.height}';
      _detected = _sent = 0;
      _statsAt = now;
    }
  }

  Future<void> _encodeAndSend(Uint8List nv21, int w, int h, int rot) async {
    try {
      final jpeg = await _jpeg.invokeMethod<Uint8List>('encode', {
        'nv21': nv21,
        'width': w,
        'height': h,
        'rotation': rot,
        'maxSide': server.videoMaxSide,
        'quality': server.videoQuality,
      });
      if (jpeg != null && server.videoOn.value) {
        server.sendFrame(jpeg);
        _sent++;
      }
    } catch (e) {
      debugPrint('jpeg encode failed: $e');
    }
  }

  Future<void> _detect(Uint8List nv21, int w, int h, int rot) async {
    try {
      final found = await _detector.processImage(InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(w.toDouble(), h.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(rot)!,
          format: InputImageFormat.nv21,
          bytesPerRow: w,
        ),
      ));
      // ML Kit 좌표는 회전 보정된 이미지 기준
      final uw = (rot % 180 == 0 ? w : h).toDouble(), uh = (rot % 180 == 0 ? h : w).toDouble();
      const unit = Rect.fromLTWH(0, 0, 1, 1);
      faces.value = [
        for (final f in found)
          (
            id: f.trackingId,
            box: Rect.fromLTRB(f.boundingBox.left / uw, f.boundingBox.top / uh,
                    f.boundingBox.right / uw, f.boundingBox.bottom / uh)
                .intersect(unit),
          ),
      ];
      _detected++;
      if (server.tracking.value) _report();
    } catch (e) {
      debugPrint('face detect failed: $e');
    }
  }

  /// 화면 탭으로 추적 대상 선택. [tap] 은 프리뷰 위 0~1 좌표 (미러된 화면 기준).
  void selectAt(Offset tap) {
    final p = Offset(1 - tap.dx, tap.dy);
    for (final f in faces.value) {
      if (f.box.contains(p)) selected.value = f.id;
    }
  }

  void _report() {
    final list = faces.value;
    FaceBox? sel;
    for (final f in list) {
      if (f.id != null && f.id == selected.value) sel = f;
    }
    // 대상이 안 보이는데 얼굴이 하나뿐이면 그 얼굴로 대상을 바꾼다.
    // trackingId 는 영구 식별자가 아니므로 같은 사람이라는 보장은 없다 (id 가 바뀌면 서버가 알 수 있음).
    if (sel == null && list.length == 1) {
      sel = list.first;
      selected.value = sel.id;
    }
    final ts = DateTime.now().microsecondsSinceEpoch / 1e6;
    if (sel == null) {
      target.value = null;
      server.send({
        'type': 'track_result',
        'target': 'face',
        'found': false,
        'tracking_id': selected.value,
        'ts': ts,
      });
      return;
    }
    final b = sel.box;
    double r(double v) => (v * 10000).round() / 10000;
    // 사람이 로봇 기준 왼쪽에 있으면(이미지 왼쪽) 화면상 눈은 오른쪽을 봐야 하므로 미러
    target.value = Offset(1 - b.center.dx, b.center.dy);
    server.send({
      'type': 'track_result',
      'target': 'face',
      'found': true,
      'tracking_id': sel.id,
      'bbox': [r(b.left), r(b.top), r(b.width), r(b.height)],
      'center': [r(b.center.dx), r(b.center.dy)],
      'ts': ts,
    });
  }
}
