// 서버 표정 → 얼굴 상태 매핑과, 디버그 탭 순환을 확인한다. 서버 없이 돈다.
// 실행:  flutter test test/face_test.dart
import 'package:armchemist_head/face_screen.dart';
import 'package:armchemist_head/robot_face.dart';
import 'package:armchemist_head/server_connection.dart';
import 'package:armchemist_head/vision.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expression → RobotState', () {
    final s = Server()..connected.value = true;
    for (final (e, want) in [
      ('idle', RobotState.normal),
      ('thinking', RobotState.thinking),
      ('working', RobotState.working),
      ('done', RobotState.done),
      ('danger', RobotState.danger),
      ('error', RobotState.caution),
    ]) {
      s.expression.value = e;
      expect(robotState(s), want, reason: e);
    }
    s.connected.value = false; // 끊김
    s.status.value = '연결 실패';
    expect(robotState(s), RobotState.caution);
    s.status.value = '연결 중...';
    expect(robotState(s), RobotState.normal);
  });

  testWidgets('server drives face, debug tap cycles', (tester) async {
    final s = Server()..connected.value = true;
    await tester.binding.setSurfaceSize(const Size(800, 360));
    await tester.pumpWidget(MaterialApp(home: FaceScreen(server: s, vision: Vision(s))));
    final face = tester.widget<RobotFace>(find.byType(RobotFace)).controller;
    expect(face.value, RobotState.normal);

    s.expression.value = 'danger';
    await tester.pump(const Duration(milliseconds: 400));
    expect(face.value, RobotState.danger);

    await tester.tapAt(const Offset(400, 180)); // 테스트는 디버그 모드
    await tester.pump(const Duration(milliseconds: 400));
    expect(face.value, RobotState.sleep);
    for (final want in [RobotState.thinking, RobotState.working, RobotState.done, RobotState.normal]) {
      await tester.tapAt(const Offset(400, 180));
      await tester.pump(const Duration(milliseconds: 400));
      expect(face.value, want);
    }
    expect(tester.takeException(), isNull);
  });
}
