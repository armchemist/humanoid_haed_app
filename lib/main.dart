import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'face_screen.dart';
import 'server_connection.dart';
import 'vision.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 로봇 얼굴이므로 상태바/내비게이션바를 숨긴다. 세로·가로 모두 허용.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final server = Server();
  await server.loadSettings();
  runApp(HeadApp(server: server, vision: Vision(server)));
}

class HeadApp extends StatefulWidget {
  const HeadApp({super.key, required this.server, required this.vision});
  final Server server;
  final Vision vision;

  @override
  State<HeadApp> createState() => _HeadAppState();
}

class _HeadAppState extends State<HeadApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.server.start();
  }

  /// 포그라운드에서만 서버 연결·카메라를 유지한다. 백그라운드 서비스는 없다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        widget.vision.paused = false;
        widget.server.start();
      case AppLifecycleState.paused || AppLifecycleState.detached:
        widget.vision.paused = true;
        widget.server.stop();
      default:
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.vision.dispose();
    widget.server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ARMchemist Head',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark)),
      home: FaceScreen(server: widget.server, vision: widget.vision),
    );
  }
}
