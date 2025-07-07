import asyncio
import json
import threading
import time
import queue
from fastapi import WebSocket
from cartesia import Cartesia

# === CONFIG ===
CARTESIA_API_KEY = 'sk_car_3vt7G9MRLjkkwa1dE1ZaUi'
SAMPLE_RATE = 16000

# === Global ===
cartesia = Cartesia(api_key=CARTESIA_API_KEY)

GENDER_VOICE_MAP = {
    "MALE": "c99d36f3-5ffd-4253-803a-535c1bc9c306",
    "FEMALE": "bc46586b-b463-4367-a96e-44127177a521",
    "NEUTRAL": "c99d36f3-5ffd-4253-803a-535c1bc9c306",
}

def parse_script_from_string(script_text):
    parsed = []
    for line in script_text.splitlines():
        line = line.strip()
        if not line:
            continue
        if ':' in line:
            speaker, dialogue = line.split(':', 1)
            parsed.append({"speaker": speaker.strip().upper(), "line": dialogue.strip()})
    return parsed

def speak(text, voice_id, tts_queue, is_speaking_flag):
    while is_speaking_flag[0]:
        time.sleep(0.05)
    tts_queue.put((text, voice_id))

def tts_worker(ws: WebSocket, loop, tts_queue, ack_queue, speak_lock, is_speaking_flag):
    while True:
        text, voice_id = tts_queue.get()
        try:
            with speak_lock:
                is_speaking_flag[0] = True
                print(f"[TTS] Speaking ({voice_id}): {text}")
                output = cartesia.tts.bytes(
                    model_id="sonic-2",
                    transcript=text,
                    voice={"mode": "id", "id": voice_id},
                    language="en",
                    output_format={
                        "container": "raw",
                        "encoding": "pcm_s16le",
                        "sample_rate": SAMPLE_RATE
                    }
                )
                raw_bytes = b"".join(output)

                asyncio.run_coroutine_threadsafe(
                    ws.send_text(json.dumps({"tts_text": text})), loop
                ).result()
                time.sleep(0.1)
                asyncio.run_coroutine_threadsafe(
                    ws.send_bytes(raw_bytes), loop
                ).result()

                print("[TTS] Waiting for frontend to finish playback...")
                ack_queue.get()  # This blocks until frontend sends done
                print("[TTS] Frontend confirmed playback done.")

        except Exception as e:
            print("[TTS Error]", e)
        finally:
            is_speaking_flag[0] = False
            tts_queue.task_done()

def start_tts_thread(ws, loop, tts_queue, ack_queue, speak_lock, is_speaking_flag):
    threading.Thread(
        target=tts_worker,
        args=(ws, loop, tts_queue, ack_queue, speak_lock, is_speaking_flag),
        daemon=True
    ).start()

async def wait_until_tts_done(tts_queue):
    while not tts_queue.empty():
        await asyncio.sleep(0.1)

async def listen_for_ack(websocket: WebSocket, ack_queue: queue.Queue):
    while True:
        try:
            recv = await websocket.receive()
            if isinstance(recv, bytes):
                continue  # ignore raw audio
            result = json.loads(recv["text"])
            print(result)
            if result.get("done") is True:
                print("[ACK] Received playback done from frontend")
                ack_queue.put(True)
        except Exception as e:
            print("[Ack Listener Error]", e)
            break

async def _run_session(script_text, user_roles, ai_character_genders, websocket,
                       tts_queue, ack_queue, is_speaking_flag):
    script = parse_script_from_string(script_text)
    print(f"[Session] Roles: {user_roles}")

    listener_task = asyncio.create_task(listen_for_ack(websocket, ack_queue))

    for entry in script:
        speaker = entry['speaker']
        line = entry['line']

        if speaker in ai_character_genders:
            gender = ai_character_genders[speaker].upper()
            voice_id = GENDER_VOICE_MAP.get(gender, GENDER_VOICE_MAP["NEUTRAL"])
            speak(line, voice_id, tts_queue, is_speaking_flag)

    await wait_until_tts_done(tts_queue)
    tts_queue.join()
    listener_task.cancel()
    print("[Session] Complete.")