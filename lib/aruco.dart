import 'package:flutter/services.dart';

/// ArUco 마커 하나. corners 는 0~1 정규화 좌표 4개 (왼쪽 위부터 시계 방향, OpenCV 순서)이고
/// 서버로 보내는 JPEG 과 같은 기준이다 (회전 보정됨, 좌우 미러 아님). sidePx 는 카메라 원본 해상도 기준 변 길이.
typedef Marker = ({int id, List<Offset> corners, double sidePx});

/// 한 프레임의 검출 결과. markers 는 큰 것부터. width/height 는 검출한 (회전 보정된) 이미지 크기 px.
typedef MarkerFrame = ({List<Marker> markers, int width, int height, double ms});

/// 중앙 서버(central/aruco.py)와 같은 사전. 바꾸려면 Aruco.kt 와 서버 reagents.json 을 같이 바꾼다.
const arucoDictionary = 'DICT_4X4_50';

const _channel = MethodChannel('armchemist/aruco');

/// 카메라 NV21 프레임에서 마커를 찾는다 (Android OpenCV, android/.../Aruco.kt).
/// [rotation] 은 이미지를 똑바로 세우는 시계 방향 회전각 (0/90/180/270).
Future<MarkerFrame> detectMarkers(Uint8List nv21, int width, int height, int rotation) async {
  final r = await _channel.invokeMapMethod<String, Object?>('detect', {
    'nv21': nv21,
    'width': width,
    'height': height,
    'rotation': rotation,
  });
  return parseMarkerFrame(r!);
}

MarkerFrame parseMarkerFrame(Map<Object?, Object?> r) => (
      markers: [
        for (final m in (r['markers'] as List).cast<Map>())
          (
            id: m['id'] as int,
            corners: [
              for (var k = 0; k < 8; k += 2)
                Offset(((m['corners'] as List)[k] as num).toDouble(), ((m['corners'] as List)[k + 1] as num).toDouble()),
            ],
            sidePx: (m['side_px'] as num).toDouble(),
          ),
      ],
      width: r['width'] as int,
      height: r['height'] as int,
      ms: (r['ms'] as num).toDouble(),
    );

/// 서버로 보내는 aruco_result. 형식은 서버 Detector.detect() 결과에 맞췄다 (ids 정렬·중복 제거, markers 큰 것부터).
/// 단, corners 는 px 가 아니라 0~1 정규화 좌표이고 size 가 검출 해상도다.
Map<String, Object?> arucoResultMessage(MarkerFrame f, double ts) {
  double r(double v) => (v * 10000).round() / 10000;
  return {
    'type': 'aruco_result',
    'dictionary': arucoDictionary,
    'ids': ({for (final m in f.markers) m.id}.toList()..sort()),
    'markers': [
      for (final m in f.markers)
        {
          'id': m.id,
          'corners': [for (final c in m.corners) [r(c.dx), r(c.dy)]],
          'side_px': (m.sidePx * 10).round() / 10,
        },
    ],
    'size': [f.width, f.height],
    'ms': (f.ms * 10).round() / 10,
    'ts': ts,
  };
}
