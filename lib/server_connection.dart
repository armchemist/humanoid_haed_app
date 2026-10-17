import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

const expressions = ['idle', 'thinking', 'working', 'danger', 'done', 'error'];

/// 상태별 기본 문구. 서버가 message 를 비워 보내면 이걸 쓴다.
const defaultMessages = {
  'idle': '실험 명령을 기다리고 있어요',
  'thinking': '실험 순서를 계획하고 있어요',
  'working': '작업을 하고 있어요',
  'done': '실험이 완료되었습니다',
  'danger': '위험 상황이에요. 확인해 주세요',
  'error': '오류가 발생했어요',
};

/// 빌드 시 `--dart-define=SERVER_URL=http://PC_IP:8100` 로 기본 서버 주소를 바꿀 수 있다.
/// 설정 화면에서 저장한 값이 있으면 그것이 우선.
const _defaultServerUrl =
    String.fromEnvironment('SERVER_URL', defaultValue: 'http://100.64.0.1:8100');

/// 중앙 서버(FastAPI)와의 통신. 앱 전체에서 하나만 만든다.
///
/// - GET  /health          : 연결 확인
/// - WS   /ws/phone        : 상태·제어 (hello, expression, state, track, video, status, track_result)
/// - WS   /ws/phone/video  : JPEG 바이너리 프레임 (사용자가 켰거나 서버가 켰을 때)
class Server {
  Server() {
    // 카메라/전송/추적 상태가 바뀔 때마다 서버에 status 를 보고한다.
    Listenable.merge([cameraOn, videoOn, tracking]).addListener(sendStatus);
  }

  String baseUrl = _defaultServerUrl;
  String deviceId = 'phone1';
  String apiKey = '';

  // 영상 전송 설정. 20mm 마커가 영상에서 25px 이상 나와야 하므로 거리가 멀면 highRes·maxSide 를 올린다.
  int videoFps = 2;
  int videoMaxSide = 640;
  int videoQuality = 70;
  bool videoHighRes = false; // true 면 카메라를 1280x720 급으로 연다 (다음에 카메라를 열 때 적용)
  bool autoVideo = false; // 서버에 연결되면 영상 전송을 자동으로 시작

  final connected = ValueNotifier(false);
  final status = ValueNotifier('연결 안 됨');
  final expression = ValueNotifier('idle');

  /// 얼굴 아래 상태 문구. 비어 있으면 [defaultMessages] 를 쓴다.
  final message = ValueNotifier('');

  /// 얼굴 추적을 해야 하는가. 서버의 track start/stop 과 앱 UI 가 모두 이 값을 바꾼다.
  final tracking = ValueNotifier(false);
  final cameraOn = ValueNotifier(false); // Vision 이 갱신
  final videoOn = ValueNotifier(false);

  IOWebSocketChannel? _ctrl;
  IOWebSocketChannel? _video;
  Timer? _retry;
  bool _active = false; // 포그라운드에서 연결을 유지해야 하는가
  int _gen = 0; // stop() 이후 늦게 끝난 연결 시도를 버리기 위한 세대 번호

  Map<String, String> get _headers => apiKey.isEmpty ? {} : {'X-API-Key': apiKey};
  Uri _ws(String path) => Uri.parse(baseUrl.replaceFirst(RegExp('^http'), 'ws') + path);

  Future<void> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? baseUrl;
    deviceId = p.getString('deviceId') ?? deviceId;
    apiKey = p.getString('apiKey') ?? apiKey;
    videoFps = p.getInt('videoFps') ?? videoFps;
    videoMaxSide = p.getInt('videoMaxSide') ?? videoMaxSide;
    videoQuality = p.getInt('videoQuality') ?? videoQuality;
    videoHighRes = p.getBool('videoHighRes') ?? videoHighRes;
    autoVideo = p.getBool('autoVideo') ?? autoVideo;
  }

  Future<void> saveSettings(String url, String id, String key,
      {int? fps, int? maxSide, int? quality, bool? highRes, bool? auto}) async {
    baseUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!baseUrl.startsWith('http')) baseUrl = 'http://$baseUrl';
    deviceId = id.trim().isEmpty ? 'phone1' : id.trim();
    apiKey = key.trim();
    videoFps = (fps ?? videoFps).clamp(1, 10);
    videoMaxSide = (maxSide ?? videoMaxSide).clamp(240, 1920);
    videoQuality = (quality ?? videoQuality).clamp(30, 95);
    videoHighRes = highRes ?? videoHighRes;
    autoVideo = auto ?? autoVideo;
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', baseUrl);
    await p.setString('deviceId', deviceId);
    await p.setString('apiKey', apiKey);
    await p.setInt('videoFps', videoFps);
    await p.setInt('videoMaxSide', videoMaxSide);
    await p.setInt('videoQuality', videoQuality);
    await p.setBool('videoHighRes', videoHighRes);
    await p.setBool('autoVideo', autoVideo);
    await reconnect();
  }

  // --- 제어 연결 ---------------------------------------------------------------

  Future<void> start() async {
    _active = true;
    await _connect();
  }

  /// 연결을 모두 닫고 재연결도 멈춘다 (백그라운드 진입, 앱 종료).
  void stop() {
    _active = false;
    _gen++;
    _retry?.cancel();
    _ctrl?.sink.close();
    _ctrl = null;
    stopVideo();
    connected.value = false;
    status.value = '연결 안 됨';
  }

  Future<void> reconnect() async {
    stop();
    await start();
  }

  Future<void> _connect() async {
    _retry?.cancel();
    if (!_active || _ctrl != null) return;
    final gen = _gen;
    // 재시도 중에는 마지막 실패 사유를 남겨 둔다 (얼굴이 idle/error 로 깜빡이지 않게).
    if (!status.value.startsWith('연결 실패')) status.value = '연결 중… $baseUrl';
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/health'), headers: _headers)
          .timeout(const Duration(seconds: 3));
      if (r.statusCode != 200) throw 'GET /health → ${r.statusCode}';

      final ch = IOWebSocketChannel.connect(_ws('/ws/phone'),
          headers: _headers, connectTimeout: const Duration(seconds: 3));
      await ch.ready;
      if (gen != _gen) {
        ch.sink.close(); // 기다리는 사이 stop()/reconnect() 됨
        return;
      }
      _ctrl = ch;
      ch.stream.listen(_onMessage,
          onDone: () => _lost(ch, '서버가 연결을 닫음'),
          onError: (e) => _lost(ch, '$e'),
          cancelOnError: true);
      send({'type': 'hello', 'device_id': deviceId, 'capabilities': ['camera', 'tracking', 'face']});
      sendStatus();
      connected.value = true;
      status.value = '연결됨 $baseUrl';
      if (autoVideo) startVideo();
    } catch (e) {
      if (gen == _gen) _fail('$e');
    }
  }

  void _lost(IOWebSocketChannel ch, String why) {
    if (_ctrl != ch) return;
    _ctrl = null;
    _fail(why);
  }

  void _fail(String why) {
    connected.value = false;
    status.value = '연결 실패: $why';
    // 포그라운드에 있는 동안만 3초마다 재시도
    if (_active) _retry = Timer(const Duration(seconds: 3), _connect);
  }

  void _onMessage(dynamic data) {
    final Map msg;
    try {
      msg = jsonDecode(data as String) as Map;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'expression':
        if (expressions.contains(msg['value'])) {
          expression.value = msg['value'];
          message.value = '';
        }
      case 'state': // {"type":"state","state":"working","message":"시약을 붓고 있어요"}
        if (expressions.contains(msg['state'])) {
          expression.value = msg['state'];
          message.value = (msg['message'] ?? '').toString();
        }
      case 'track':
        if ((msg['target'] ?? 'face') == 'face') tracking.value = msg['action'] == 'start';
      case 'video':
        msg['action'] == 'start' ? startVideo() : stopVideo();
    }
  }

  void send(Map<String, Object?> msg) => _ctrl?.sink.add(jsonEncode(msg));

  void sendStatus() => send({
        'type': 'status',
        'camera': videoOn.value ? 'streaming' : (cameraOn.value ? 'preview' : 'off'),
        'tracking': tracking.value,
      });

  // --- 영상 연결 ---------------------------------------------------------------

  Future<void> startVideo() async {
    if (_video != null) return;
    try {
      final ch = IOWebSocketChannel.connect(_ws('/ws/phone/video'),
          headers: _headers, connectTimeout: const Duration(seconds: 3));
      await ch.ready;
      ch.sink.add(jsonEncode({'type': 'hello', 'device_id': deviceId}));
      _video = ch;
      videoOn.value = true;
      // 서버가 끊으면 전송도 멈춘다. 제어 연결이 다시 붙을 때 autoVideo 면 재개된다.
      ch.stream.listen((_) {}, onDone: () {
        if (_video == ch) stopVideo();
      }, onError: (_) {}, cancelOnError: true);
    } catch (e) {
      status.value = '영상 연결 실패: $e';
    }
  }

  void stopVideo() {
    _video?.sink.close();
    _video = null;
    videoOn.value = false;
  }

  // ponytail: 소켓 송신 버퍼는 확인하지 않는다. 1~3 FPS 소형 JPEG 이라 LAN 에선 충분.
  // 느린 망에서 밀리면 서버 ack 를 받고 다음 프레임을 보내는 방식으로 바꿀 것.
  void sendFrame(Uint8List jpeg) => _video?.sink.add(jpeg);
}
