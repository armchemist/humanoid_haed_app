import 'package:armchemist_head/aruco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Aruco.kt 가 MethodChannel 로 돌려주는 모양
  final raw = <Object?, Object?>{
    'markers': [
      {'id': 3, 'corners': [0.5, 0.25, 0.6, 0.25, 0.6, 0.35, 0.5, 0.35], 'side_px': 64.04},
      {'id': 1, 'corners': [0.1, 0.1, 0.12, 0.1, 0.12, 0.12, 0.1, 0.12], 'side_px': 12.8},
      {'id': 3, 'corners': [0.8, 0.8, 0.81, 0.8, 0.81, 0.81, 0.8, 0.81], 'side_px': 6.4},
    ],
    'width': 640,
    'height': 480,
    'ms': 7.25,
  };

  test('parseMarkerFrame', () {
    final f = parseMarkerFrame(raw);
    expect(f.markers, hasLength(3));
    expect(f.markers.first.id, 3);
    expect(f.markers.first.corners, const [Offset(0.5, 0.25), Offset(0.6, 0.25), Offset(0.6, 0.35), Offset(0.5, 0.35)]);
    expect(f.markers.first.sidePx, 64.04);
    expect((f.width, f.height, f.ms), (640, 480, 7.25));
  });

  test('aruco_result: ids 정렬·중복 제거, 서버 Detector.detect 와 같은 키', () {
    final m = arucoResultMessage(parseMarkerFrame(raw), 12.5);
    expect(m['type'], 'aruco_result');
    expect(m['dictionary'], 'DICT_4X4_50');
    expect(m['ids'], [1, 3]);
    expect(m['size'], [640, 480]);
    expect(m['ms'], 7.3);
    final first = (m['markers'] as List).first as Map;
    expect(first, {
      'id': 3,
      'corners': [[0.5, 0.25], [0.6, 0.25], [0.6, 0.35], [0.5, 0.35]],
      'side_px': 64.0,
    });
  });

  test('마커 없음', () {
    final m = arucoResultMessage(parseMarkerFrame({'markers': [], 'width': 1, 'height': 1, 'ms': 0}), 0);
    expect(m['ids'], isEmpty);
    expect(m['markers'], isEmpty);
  });
}
