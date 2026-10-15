"""휴대폰 앱 테스트용 목(mock) 중앙 서버.

실제 ARMchemist 중앙 서버가 아니다. 중앙 서버가 아직 없어서, 앱이 프롬프트에
정의된 통신 규약대로 동작하는지 확인하려고 만든 최소 구현이다.
중앙 서버가 생기면 이 파일이 아니라 그쪽 구현을 기준으로 다시 검증할 것.

실행:
    pip install fastapi "uvicorn[standard]"
    python mock_server.py            # 0.0.0.0:8100

확인:
    curl -X POST localhost:8100/phone/phone1/expression -H "Content-Type: application/json" -d "{\"value\":\"danger\"}"
    curl -X POST localhost:8100/phone/phone1/track -H "Content-Type: application/json" -d "{\"action\":\"start\",\"target\":\"face\"}"
    브라우저에서 http://<PC IP>:8100/latest.jpg  (마지막으로 받은 프레임)
"""

import json
import os
import time

import uvicorn
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import Response

API_KEY = os.environ.get("API_KEY") or None  # 설정하면 X-API-Key 헤더 검사

app = FastAPI()
phones: dict[str, WebSocket] = {}
last: dict[str, dict] = {}  # device -> {메시지 type: 마지막 메시지}
latest_jpeg = b""
frame_count = 0


def _key_ok(ws: WebSocket) -> bool:
    return not API_KEY or ws.headers.get("x-api-key") == API_KEY


@app.get("/health")
def health():
    return {"ok": True, "phones": list(phones), "frames": frame_count}


@app.websocket("/ws/phone")
async def ws_phone(ws: WebSocket):
    if not _key_ok(ws):
        await ws.close(code=1008)
        return
    await ws.accept()
    hello = json.loads(await ws.receive_text())
    device = hello.get("device_id", "phone1")
    print("[ctrl] hello", hello)
    phones[device] = ws
    try:
        while True:
            text = await ws.receive_text()
            print(f"[ctrl] {device}:", text)
            msg = json.loads(text)
            last.setdefault(device, {})[msg.get("type")] = msg
    except WebSocketDisconnect:
        print(f"[ctrl] {device} disconnected")
    finally:
        if phones.get(device) is ws:
            del phones[device]


@app.websocket("/ws/phone/video")
async def ws_video(ws: WebSocket):
    global latest_jpeg, frame_count
    if not _key_ok(ws):
        await ws.close(code=1008)
        return
    await ws.accept()
    print("[video] hello", await ws.receive_text())
    t0, n = time.time(), 0
    try:
        while True:
            data = await ws.receive_bytes()
            if data[:2] != b"\xff\xd8":
                print("[video] JPEG 아님:", data[:8])
                continue
            latest_jpeg, n = data, n + 1
            frame_count += 1
            print(f"[video] frame {n} {len(data)} bytes, {n / (time.time() - t0):.1f} fps")
    except WebSocketDisconnect:
        print("[video] disconnected")


@app.get("/phone/{device}/state")
def state(device: str):
    """폰이 마지막으로 보낸 status 와 track_result."""
    return {"connected": device in phones, **last.get(device, {})}


@app.get("/latest.jpg")
def latest():
    if not latest_jpeg:
        raise HTTPException(404, "아직 받은 프레임 없음")
    return Response(latest_jpeg, media_type="image/jpeg")


async def _send(device: str, msg: dict):
    ws = phones.get(device)
    if not ws:
        raise HTTPException(404, f"{device} 미연결")
    await ws.send_text(json.dumps(msg))
    return {"sent": msg}


@app.post("/phone/{device}/expression")
async def expression(device: str, body: dict):
    return await _send(device, {"type": "expression", "value": body["value"]})


@app.post("/phone/{device}/track")
async def track(device: str, body: dict):
    return await _send(device, {"type": "track", "action": body["action"], "target": body.get("target", "face")})


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8100)
