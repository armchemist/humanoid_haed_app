# phone_app — ARMchemist 휴머노이드 머리 (Android, Flutter POC)

스마트폰을 로봇 머리로 쓴다. 화면 = 얼굴, 전면 카메라 = 눈.
중앙 FastAPI 서버의 명령에 따라 표정이 바뀌고, 전면 카메라 JPEG 영상과 선택한 얼굴의 추적 결과를 서버로 보낸다.

## 구조

| 파일 | 내용 |
| --- | --- |
| `lib/main.dart` | 초기화, 앱 생명주기 (백그라운드 진입 시 카메라·소켓 해제) |
| `lib/server_connection.dart` | `GET /health`, `WS /ws/phone`, `WS /ws/phone/video`, 재연결, 영상 설정(FPS·크기·품질) |
| `lib/face_screen.dart` | 얼굴/표정 (CustomPainter), 하단 상태 문구, 연결 표시, 설정 대화상자 |
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
flutter build apk --debug --dart-define=SERVER_URL=http://<PC IP>:8100   # 기본 서버 주소를 박아서 빌드
adb install -r build/app/outputs/flutter-apk/app-debug.apk                # -r: 기존 설치 위에 갱신 (설정 보존)
```

`--dart-define=SERVER_URL` 은 설정 화면에서 저장한 값이 없을 때의 기본값이다. 생략하면 `http://100.64.0.1:8100`.

`android/gradle.properties` 의 `kotlin.incremental=false` 는 지우지 말 것. 프로젝트(D:)와 pub 캐시(C:)가
다른 드라이브면 Kotlin 증분 캐시가 깨져 빌드가 실패한다.

## 서버 연결

1. PC에서 중앙 서버 실행 (`PiSensorServer/central`):
   ```bash
   cd PiSensorServer
   python -m uvicorn central.main:app --host 0.0.0.0 --port 8100
   ```
   중앙 서버 없이 앱만 확인할 때는 테스트용 목 서버를 쓴다:
   ```bash
   cd tools && python -m venv .venv && .venv/Scripts/pip install fastapi "uvicorn[standard]"
   .venv/Scripts/python mock_server.py      # 0.0.0.0:8100
   ```
2. 앱 오른쪽 위 ⚙ → 서버 주소에 PC의 LAN 또는 Tailscale IP 입력 (`http://100.x.x.x:8100`).
   폰에서 `localhost` 는 폰 자신이다. 에뮬레이터에서는 `http://10.0.2.2:8100`.
   Windows 방화벽에서 8100 포트 인바운드를 허용해야 할 수 있다.
3. 서버에 `API_KEY` 가 있으면 같은 값을 API 키 칸에 넣는다. HTTP와 두 WebSocket 모두 `X-API-Key` 헤더로 보낸다 (쿼리스트링 아님).

연결 실패 시 3초마다 재시도한다 (앱이 포그라운드에 있을 때만). 상태 문구를 누르면 즉시 재연결.

## 상태 확인 (중앙 서버)

```bash
curl http://127.0.0.1:8100/status                        # phones.phone1: 연결, status, last_track, video
curl http://127.0.0.1:8100/phone/phone1/frame -o f.jpg   # 마지막 카메라 프레임
```

브라우저에서 `http://127.0.0.1:8100/docs` → 엔드포인트 선택 → **Try it out** → **Execute**.

| 엔드포인트 | 확인 내용 |
| --- | --- |
| `GET /status` | 폰 연결 여부, 마지막 `status`, `last_track` |
| `POST /phone/{device_id}/expression` | `{"value": "danger"}` → 폰 표정이 즉시 바뀜 |
| `POST /phone/{device_id}/track` | `{"action": "start", "target": "face"}` / `"stop"` |
| `GET /phone/{device_id}/frame` | 마지막 JPEG (앱에서 `영상 전송`을 켜야 함) |

서버에 `API_KEY` 가 설정돼 있으면 각 엔드포인트의 `x-api-key` 칸에 넣는다.

에뮬레이터로 테스트할 때:
```bash
D:\Android\Sdk\emulator\emulator.exe -avd Pixel_10 -camera-front emulated
flutter run -d emulator-5554     # 앱 서버 주소: http://10.0.2.2:8100
```

`test/protocol_test.dart` 는 목 서버 전용 필드(`phones`, `frames`)를 확인하므로 목 서버에서만 돌린다.

## 화면

- **얼굴 화면**: 서버 `state`/`expression` 반영. 눈이 중심이고 아래에 짧은 상태 문구(서버 `message`, 비면 상태별 기본 문구).
  서버와 끊기면 서버 상태를 유지하지 않고 X 눈 + "서버 연결이 끊어졌어요". 영상 전송 중이면 "● 카메라 전송 중" 이 작게 보인다.
  길게 누르면 수동 테스트 패널(표정·추적·영상 전송). 🎥 → 카메라 화면.

  | 상태 | 눈 | 기본 문구 |
  | --- | --- | --- |
  | `idle` | 기본, 깜빡임 | 실험 명령을 기다리고 있어요 |
  | `thinking` | 시선 위로, 한쪽 눈 작게 | 실험 순서를 계획하고 있어요 |
  | `working` | 눈 반쯤, 눈썹 | 작업을 하고 있어요 |
  | `done` | ^ ^ | 실험이 완료되었습니다 |
  | `danger` | 크게 뜬 눈, 붉은 배경 | 위험 상황이에요. 확인해 주세요 |
  | `error` | X X | 오류가 발생했어요 |

  ArUco 확인 중에는 서버가 자동으로 `working`("시약 3 시약을 확인하고 있어요") → `done`("시약을 확인했어요") / `danger`("선택한 시약이 다릅니다") 를 보낸다.
  **ID 일치는 '시약 일치 확인'일 뿐 파지 성공이 아니다.**
- **설정(⚙)**: 서버 주소, device_id, 영상 FPS(기본 2)·긴 변 px(640)·JPEG 품질(70), 카메라 고해상도(1280x720, 다음 카메라 열 때 적용),
  연결되면 영상 전송 자동 시작.
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
- 서버가 `video start` 를 보내면(웹 UI 버튼, `/verify/start`) 얼굴 화면을 유지한 채 카메라를 열어 JPEG 를 보낸다.
  얼굴 추적과 영상 전송은 같은 카메라 스트림을 쓰므로 카메라가 두 번 열리지 않는다.
- 20mm ArUco 마커는 긴 변 640px 영상에서 약 30cm 이내여야 25px 이상으로 보인다. 더 멀면 고해상도·긴 변 px 를 올린다 (전송량·인코딩 시간 증가).
- 카메라는 카메라 화면·추적·영상 전송 중 하나라도 켜져 있을 때만 열린다. 백그라운드로 가면 닫힌다.

## 보안 주의 (POC 전용)

`AndroidManifest.xml` 의 `android:usesCleartextTraffic="true"` 는 LAN/Tailscale 안에서 `http://`, `ws://` 를 쓰기 위한 것이다.
인터넷에 공개되는 서버용 설정이 아니다. 외부 공개 시 HTTPS/WSS 로 바꾸고 이 속성을 지울 것.
