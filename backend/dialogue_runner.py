import asyncio
import json
import threading
import time
import queue
from fastapi import WebSocket
from fastapi import WebSocketDisconnect
from cartesia import Cartesia
from rapidfuzz import fuzz
from fastapi import WebSocketDisconnect

# === CONFIG ===
#CARTESIA_API_KEY = 'sk_car_3vt7G9MRLjkkwa1dE1ZaUi'
#sk_car_NzViPviNKhRTuYZ3tNdfFj
CARTESIA_API_KEY = 'sk_car_9dgHRAyxp3d6853MKLb6WU'
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
                ack_queue.get()
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

# ✅ New unified listener for both ACK and STT
async def websocket_message_router(websocket: WebSocket, ack_queue: queue.Queue, expected_user_lines_queue: queue.Queue, tts_queue: queue.Queue, is_speaking_flag: list):
    while True:
        try:
            recv = await websocket.receive()
            if isinstance(recv, bytes):
                continue
            result = json.loads(recv["text"])

            if "transcript" in result:
                user_input = result["transcript"].strip()
                if not expected_user_lines_queue.empty():
                    expected_line = expected_user_lines_queue.queue[0]
                    similarity = fuzz.ratio(user_input.lower(), expected_line.lower())
                    
                    print(f"[STT] Score: {similarity}")

                    if similarity >= 50:
                        # === SUCCESS SCENARIO ===
                        print("[STT] Match! Triggering Positive Beep.")
                        await asyncio.sleep(0.8)
                        
                        # 1. Send Success Event (Plays Positive Beep)
                        await websocket.send_text(json.dumps({"event": "success"}))
                        
                        # 2. Short pause so the beep doesn't overlap with the next action
                        await asyncio.sleep(0.5) 
                        
                        # 3. Send Advance Event (Moves Script Highlighter)
                        await websocket.send_text(json.dumps({"event": "advance"}))
                        
                        expected_user_lines_queue.get()

                    else:
                        # === FAILURE SCENARIO ===
                        print("[STT] No match. Triggering Error Beep.")
                        await asyncio.sleep(0.8)
                        # 1. Send Retry Event (Plays Error Beep)
                        await websocket.send_text(json.dumps({"event": "retry"}))
                        
                        # 2. Wait for beep to finish
                        await asyncio.sleep(0.8) 

                        # 3. Re-open Mic
                        await websocket.send_text(json.dumps({"next_turn": "user"}))

            elif result.get("done") is True:
                ack_queue.put(True)

        except Exception as e:
            print("[Router Error]", e)
            break
async def _run_session(script_text, user_roles, ai_character_genders, websocket,
                       tts_queue, ack_queue, is_speaking_flag):
    script = parse_script_from_string(script_text)
    print(f"[Session] Roles: {user_roles}")

    expected_user_lines_queue = queue.Queue()
    router_task = asyncio.create_task(websocket_message_router(websocket, ack_queue, expected_user_lines_queue, tts_queue, is_speaking_flag))
    #ADDED
    await asyncio.sleep(0.1)
    #ADDED
    chk=False
    if script and script[0]['speaker'] in user_roles:
        first_line = script[0]['line']
        expected_user_lines_queue.put(first_line)
        await websocket.send_text(json.dumps({"next_turn": "user"}))
        print("[Init] First line is user - mic started")
        while not expected_user_lines_queue.empty() and expected_user_lines_queue.queue[0] == first_line:
            await asyncio.sleep(0.1)
        chk = True


    idx=0
    for entry in script:
        idx=idx+1
        speaker = entry['speaker']
        line = entry['line']

        if speaker in ai_character_genders:
            gender = ai_character_genders[speaker].upper()
            voice_id = GENDER_VOICE_MAP.get(gender, GENDER_VOICE_MAP["NEUTRAL"])
            speak(line, voice_id, tts_queue, is_speaking_flag)
            while is_speaking_flag[0] or not tts_queue.empty():
                await asyncio.sleep(0.1)
            # #ADDED
            # await wait_until_tts_done(tts_queue)
            # #ADDED
        # elif speaker in user_roles:
        #     print(f"[Awaiting User Line]: {line}")
        #     expected_user_lines_queue.put(line)
        #     while not expected_user_lines_queue.empty():
        #         await asyncio.sleep(0.1)
        elif speaker in user_roles:
            if(idx==1 and chk):
                print("[Loop] Skipping first user line (already handled)")
                continue
            print(f"[Awaiting User Line]: {line}")
            expected_user_lines_queue.put(line)

            await websocket.send_text(json.dumps({"next_turn": "user"}))
            print("[Backend] Informed frontend: Start user mic (first user line)")

            # Wait until this specific line is matched and dequeued
            while not expected_user_lines_queue.empty() and expected_user_lines_queue.queue[0] == line:
                await asyncio.sleep(0.1)

                # await asyncio.sleep(0.1)

    await asyncio.sleep(0.1)
    print("[Session] Waiting for final TTS (if any) to finish...")
    await wait_until_tts_done(tts_queue)
    
    # last_text="The script has ended. Thank you"
    # voice_id=GENDER_VOICE_MAP["NEUTRAL"]
    # speak(last_text,voice_id,tts_queue,is_speaking_flag)

    # Use your speak wrapper for consistent playback handling
    goodbye_text = "The script has ended. Thank you"
    voice_id = GENDER_VOICE_MAP["NEUTRAL"]
    speak(goodbye_text, voice_id, tts_queue, is_speaking_flag)

    # Wait until it's spoken
    while is_speaking_flag[0] or not tts_queue.empty():
        await asyncio.sleep(0.1)



    await asyncio.sleep(0.1)
    tts_queue.join()
    router_task.cancel()
    print("[Session] Complete.")