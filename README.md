# phone_app — ARMchemist 휴머노이드 머리 (Android, Flutter POC)

스마트폰을 로봇 머리로 쓴다. 화면 = 얼굴, 전면 카메라 = 눈.
중앙 FastAPI 서버의 명령에 따라 표정이 바뀌고, 전면 카메라 JPEG 영상과 선택한 얼굴의 추적 결과를 서버로 보낸다.

## 구조

| 파일 | 내용 |
| --- | --- |
| `lib/main.dart` | 초기화, 앱 생명주기 (백그라운드 진입 시 카메라·소켓 해제) |
| `lib/server_connection.dart` | `GET /health`, `WS /ws/phone`, `WS /ws/phone/video`, 재연결 |
| `lib/face_screen.dart` | 얼굴/표정 (CustomPainter), 연결 표시, 설정 대화상자 |
| `lib/camera_screen.dart` | 카메라 프리뷰, 얼굴 박스, 영상 전송/추적 토글 |
| `lib/vision.dart` | 전면 카메라, ML Kit 얼굴 검출·추적, JPEG 송신 |
| `android/.../MainActivity.kt` | NV21 → JPEG (Android `YuvImage`), 화면 꺼짐 방지 |
| `tools/mock_server.py` | 규약 테스트용 **목 서버** (실제 중앙 서버 아님) |
| `test/protocol_test.dart` | 서버 규약 테스트 (실행 중인 서버 필요) |

패키지: `camera`, `google_mlkit_face_detection`, `web_socket_channel`, `http`, `shared_preferences`.

## 빌드·실행 (Windows)

```bash
flutter doctor
flutter pub get
flutter run                  # USB 디버깅 켠 폰 연결 후
flutter build apk --debug    # build/app/outputs/flutter-apk/app-debug.apk
```

`android/gradle.properties` 의 `kotlin.incremental=false` 는 지우지 말 것. 프로젝트(D:)와 pub 캐시(C:)가
다른 드라이브면 Kotlin 증분 캐시가 깨져 빌드가 실패한다.

## 서버 연결

1. PC에서 서버 실행 (중앙 서버, 또는 테스트용 목 서버):
   ```bash
   cd tools && python -m venv .venv && .venv/Scripts/pip install fastapi "uvicorn[standard]"
   .venv/Scripts/python mock_server.py      # 0.0.0.0:8100
   ```
2. 앱 오른쪽 위 ⚙ → 서버 주소에 PC의 LAN 또는 Tailscale IP 입력 (`http://100.x.x.x:8100`).
   폰에서 `localhost` 는 폰 자신이다. 에뮬레이터에서는 `http://10.0.2.2:8100`.
   Windows 방화벽에서 8100 포트 인바운드를 허용해야 할 수 있다.
3. 서버에 `API_KEY` 가 있으면 같은 값을 API 키 칸에 넣는다. HTTP와 두 WebSocket 모두 `X-API-Key` 헤더로 보낸다 (쿼리스트링 아님).

연결 실패 시 3초마다 재시도한다 (앱이 포그라운드에 있을 때만). 상태 문구를 누르면 즉시 재연결.

## 화면

- **얼굴 화면**: 서버 `expression` 반영. 길게 누르면 수동 테스트 패널(표정·추적). 🎥 → 카메라 화면.
- **카메라 화면**: 전면 프리뷰, 얼굴 박스(초록 = 추적 대상), `영상 전송`, `얼굴 추적` 토글, 검출/전송 FPS.
  얼굴을 탭하면 추적 대상으로 선택된다.

## 동작 메모

- 영상: 2 FPS, 긴 변 640px, JPEG 품질 70. 회전 보정됨, **좌우 미러 아님**(프리뷰만 거울처럼 보임).
  인코딩 중에 들어온 프레임은 버린다. 서버가 영상 소켓을 끊으면 전송이 꺼지고 자동 재개하지 않는다.
- 추적: ML Kit fast 모드 + `enableTracking`, 최대 ~6 FPS, 겹쳐 실행하지 않음.
  `track_result` 의 `bbox`/`center` 는 전송 JPEG 과 같은 정규화 좌표 (`[x, y, w, h]`, 원점 왼쪽 위).
  대상이 사라졌는데 얼굴이 하나만 보이면 그 얼굴로 대상을 바꾼다. `trackingId` 는 영구 식별자가 아니므로
  같은 사람이라는 보장은 없다 — `tracking_id` 가 바뀌면 다른 대상일 수 있다.
  여러 얼굴 중 대상이 없으면 `found:false` 를 보내며 탭을 기다린다.
- 서버가 `track start` 를 보내면 카메라 화면이 아니어도 카메라를 열어 추적하고, 얼굴 화면의 눈이 대상 쪽을 본다.
- 카메라는 카메라 화면·추적·영상 전송 중 하나라도 켜져 있을 때만 열린다. 백그라운드로 가면 닫힌다.

## 보안 주의 (POC 전용)

`AndroidManifest.xml` 의 `android:usesCleartextTraffic="true"` 는 LAN/Tailscale 안에서 `http://`, `ws://` 를 쓰기 위한 것이다.
인터넷에 공개되는 서버용 설정이 아니다. 외부 공개 시 HTTPS/WSS 로 바꾸고 이 속성을 지울 것.
