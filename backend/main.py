import asyncio
from fastapi import FastAPI, File, UploadFile, Form, Depends, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from pydantic import BaseModel
from process_pdf import extract_script, get_unique_characters
from models import Script
from db import SessionLocal, engine
import hashlib
import shutil
import os
import dialogue_runner
from models import Base
import json
from cartesia import Cartesia
import json
import threading
import queue

Base.metadata.create_all(bind=engine)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def hash_script(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()



# CARTESIA_API_KEY = 'sk_car_3vt7G9MRLjkkwa1dE1ZaUi'
# THRESHOLD = 65
# SILENCE_TIMEOUT = 1.5
# SAMPLE_RATE = 16000

# cartesia = Cartesia(api_key=CARTESIA_API_KEY)
# GENDER_VOICE_MAP = {
#     "MALE": "c99d36f3-5ffd-4253-803a-535c1bc9c306",
#     "FEMALE": "bc46586b-b463-4367-a96e-44127177a521",
#     "NEUTRAL": "c99d36f3-5ffd-4253-803a-535c1bc9c306",
# }

# def parse_script(script_text):
#     parsed = []
#     for line in script_text.strip().splitlines():
#         if ':' in line:
#             speaker, line_text = line.split(':', 1)
#             parsed.append({"speaker": speaker.strip().upper(), "line": line_text.strip()})
#     return parsed

# async def wait_until_empty(q):
#     while not q.empty():
#         await asyncio.sleep(0.1)

# async def tts_sender(ws: WebSocket, queue: asyncio.Queue):
#     while True:
#         text, voice_id = await queue.get()
#         try:
#             print(f"[TTS] Speaking ({voice_id}): {text}")
#             output = cartesia.tts.bytes(
#                 model_id="sonic-2",
#                 transcript=text,
#                 voice={"mode": "id", "id": voice_id},
#                 language="en",
#                 output_format={"container": "raw", "encoding": "pcm_s16le", "sample_rate": SAMPLE_RATE}
#             )
#             raw_bytes = b''.join(output)

#             await ws.send_text(json.dumps({"tts_text": text}))
#             await asyncio.sleep(0.1)
#             print(f"[SEND] Binary len={len(raw_bytes)}")
#             await ws.send_bytes(raw_bytes)

#         except Exception as e:
#             print(f"[TTS Error] {e}")
#         finally:
#             queue.task_done()

# async def start_stt(ws: WebSocket, expected_line: str, tts_q: asyncio.Queue):
#     full_transcript = ""
#     last_time = time.time()
#     print("[STT] Waiting for user line...")

#     while True:
#         recv = await ws.receive_text()
#         data = json.loads(recv)
#         transcript = data.get("transcript", "")
#         if transcript:
#             print(f"[STT] Heard: {transcript}")
#             full_transcript += " " + transcript
#             last_time = time.time()

#         if time.time() - last_time > SILENCE_TIMEOUT and full_transcript:
#             similarity = fuzz.ratio(full_transcript.lower(), expected_line.lower())
#             print(f"[Match] {similarity}%")
#             if similarity >= THRESHOLD:
#                 return True
#             else:
#                 await tts_q.put(("Please try again", GENDER_VOICE_MAP["NEUTRAL"]))
#                 return False

# async def dialogue_session(script_text, user_roles, ai_genders, ws: WebSocket):
#     tts_q = asyncio.Queue()
#     asyncio.create_task(tts_sender(ws, tts_q))

#     script = parse_script(script_text)

#     for entry in script:
#         speaker = entry['speaker']
#         line = entry['line']

#         if speaker in user_roles:
#             await wait_until_empty(tts_q)
#             success = await start_stt(ws, line, tts_q)
#             while not success:
#                 await wait_until_empty(tts_q)
#                 success = await start_stt(ws, line, tts_q)

#         elif speaker in ai_genders:
#             voice = GENDER_VOICE_MAP.get(ai_genders[speaker].upper(), GENDER_VOICE_MAP["NEUTRAL"])
#             await tts_q.put((line, voice))

#     await wait_until_empty(tts_q)
#     await tts_q.join()
#     print("[Session Complete]")

@app.get("/")
def root():
    return {"message": "FastAPI is running :)"}

@app.post("/upload-pdf/")
async def upload_pdf(
    file: UploadFile = File(...),
    user_uid: str = Form(...),
    db: Session = Depends(get_db)
):
    file_location = f"scripts/{file.filename}"
    os.makedirs("scripts", exist_ok=True)
    with open(file_location, "wb") as f:
        shutil.copyfileobj(file.file, f)

    script_text = extract_script(file_location)
    os.remove(file_location)

    characters = get_unique_characters(script_text)
    script_hash = hash_script(script_text)

    existing = db.query(Script).filter_by(user_uid=user_uid, script_hash=script_hash).first()
    if existing:
        return {
            "message": "Script already uploaded.",
            "script_id": existing.id,
            "text": existing.original_text,
            "characters": existing.characters,
            "script_hash": script_hash,
            "user_uid": user_uid
        }

    new_script = Script(
        user_uid=user_uid,
        script_hash=script_hash,
        original_text=script_text,
        characters=characters
    )
    db.add(new_script)
    db.commit()
    db.refresh(new_script)

    return {
        "script_id": new_script.id,
        "text": new_script.original_text,
        "characters": new_script.characters,
        "script_hash": script_hash,
        "user_uid": user_uid
    }

@app.websocket("/ws-dialogue/")
async def websocket_dialogue(websocket: WebSocket):
    await websocket.accept()

    # Create session-specific resources
    tts_queue = queue.Queue()
    ack_queue = queue.Queue()
    speak_lock = threading.Lock()
    is_speaking_flag = [False]  # list to allow mutable boolean

    try:
        init_msg = await websocket.receive_text()

        try:
            data = json.loads(init_msg)
        except json.JSONDecodeError:
            await websocket.send_text("Invalid JSON format")
            await websocket.close()
            return

        # Ensure required fields exist
        if not all(k in data for k in ["script", "user_roles", "ai_character_genders"]):
            await websocket.send_text("Missing required keys in init payload")
            await websocket.close()
            return

        script_text = data["script"]
        user_roles = set(data["user_roles"])
        ai_roles = data["ai_character_genders"]

        # ✅ Start TTS thread for this user/session
        dialogue_runner.start_tts_thread(
            websocket,
            asyncio.get_running_loop(),
            tts_queue,
            ack_queue,
            speak_lock,
            is_speaking_flag
        )

        # ✅ Run the dialogue session using isolated resources
        await dialogue_runner._run_session(
            script_text,
            user_roles,
            ai_roles,
            websocket,
            tts_queue,
            ack_queue,
            is_speaking_flag
        )

    except WebSocketDisconnect:
        print("[WebSocket] Client disconnected")
    except Exception as e:
        print("[WebSocket Error]", e)
        await websocket.close()


# @app.websocket("/ws-dialogue/")
# async def websocket_endpoint(ws: WebSocket):
#     await ws.accept()
#     try:
#         payload = json.loads(await ws.receive_text())
#         print(f"[WS] Received: {payload}")
#         await dialogue_session(
#             script_text=payload["script"],
#             user_roles=set(payload["user_roles"]),
#             ai_genders=payload["ai_character_genders"],
#             ws=ws
#         )
#     except Exception as e:
#         print(f"[WebSocket Error]: {e}")
#     finally:
#         await ws.close()

# from fastapi import FastAPI, WebSocket
# from fastapi.responses import HTMLResponse
# import asyncio

# app = FastAPI()

# @app.get("/")
# async def get():
#     return HTMLResponse("""
#         <html>
#         <body>
#             <h1>WS Audio Server</h1>
#             <p>Use WebSocket to receive audio</p>
#         </body>
#         </html>
#     """)

@app.websocket("/ws/")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()

    # Wait for client to send something
    msg = await websocket.receive_text()
    print(f"[Server] Received: {msg}")

    # Send back simple text confirmation
    await websocket.send_text("🗣️ Sending you audio...")

    # Read audio bytes (a small .wav file)
    with open("../sample.wav", "rb") as f:
        audio_data = f.read()

    print(f"[Server] Sending {len(audio_data)} bytes of audio")
    await websocket.send_bytes(audio_data)

    print("[Server] Done sending.")
