// 앱의 Server 클래스가 통신 규약대로 동작하는지 실제 서버에 붙어 확인한다.
// 먼저 서버를 띄울 것:  tools/.venv/Scripts/python tools/mock_server.py
// 실행:  flutter test test/protocol_test.dart   (SERVER=http://host:8100 로 다른 서버 지정 가능)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:armchemist_head/server_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

Future<void> until(bool Function() ok) async {
  for (var i = 0; i < 50 && !ok(); i++) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  expect(ok(), isTrue);
}

void main() {
  final base = Platform.environment['SERVER'] ?? 'http://127.0.0.1:8100';
  Future<void> post(String path, Map body) => http.post(Uri.parse('$base$path'),
      headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
  Future<Map> health() async => jsonDecode((await http.get(Uri.parse('$base/health'))).body);

  test('connect, hello, expression, track, video frame', () async {
    final s = Server()..baseUrl = base;
    await s.start();
    expect(s.connected.value, isTrue, reason: s.status.value);
    await Future.delayed(const Duration(milliseconds: 300));
    expect((await health())['phones'], contains('phone1')); // hello 로 등록됨

    await post('/phone/phone1/expression', {'value': 'danger'});
    await until(() => s.expression.value == 'danger');

    await post('/phone/phone1/track', {'action': 'start', 'target': 'face'});
    await until(() => s.tracking.value);
    await post('/phone/phone1/track', {'action': 'stop', 'target': 'face'});
    await until(() => !s.tracking.value);

    final before = (await health())['frames'] as int;
    await s.startVideo();
    expect(s.videoOn.value, isTrue, reason: s.status.value);
    s.sendFrame(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]));
    await Future.delayed(const Duration(milliseconds: 300));
    expect((await health())['frames'], before + 1);

    s.stop();
    expect(s.connected.value, isFalse);
    expect(s.videoOn.value, isFalse);
  });

  test('unreachable server reports error without throwing', () async {
    final s = Server()..baseUrl = 'http://127.0.0.1:1';
    await s.start();
    expect(s.connected.value, isFalse);
    expect(s.status.value, startsWith('연결 실패'));
    s.stop();
  });
}
