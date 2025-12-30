# 🎬 SelfTape-AI

**SelfTape-AI** is a cross-platform Flutter app that lets you record self-tape scenes by performing one character while the AI performs the others using real-time text-to-speech and speech recognition. It also records your video, enabling a full acting experience.

---

## Prerequisites

- Flutter SDK installed: [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install)
- Python 3.9 with `venv`
- Deepgram API key (for STT)
- System TTS voices (Zira, David, etc.)

---

## Project Structure

```bash
.
├── backend/
│   ├── main.py
│   ├── process_pdf.py
│   └── stt.py
└── sceneapp/
    └── lib/
        ├── pages/
        │   ├── login_page.dart
        │   ├── home_page.dart
        │   ├── auth_page.dart
        │   ├── record_page.dart
        │   └── character_selection_page.dart
        ├── components/
        │   ├── button.dart
        │   ├── square_tile.dart
        │   └── text_field.dart
        ├── ip_address.dart
        └── main.dart
```

---

## Getting Started

### Install Backend Dependencies

```bash
cd backend/
python -m venv venv
# Activate the virtual environment:
source venv/bin/activate      # macOS/Linux
venv\Scripts\activate         # Windows
pip install -r requirements.txt
```
### Run the Backend

```bash
cd backend/
source venv/bin/activate
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Configure Frontend Network (Important!)

Before running the app, you must point the frontend to your computer's local network IP address.  
The app **cannot** reach the server using `localhost` if running on a physical device or emulator.

### 1. Find your computer's local IP address

- **Windows**  
  Run `ipconfig` in CMD and look for **IPv4 Address** under your Wi-Fi adapter.

- **Mac/Linux**  
  Run `ifconfig` or check **Network Settings**.

### 2. Open the file

```text
sceneapp/lib/ip_address.dart
```

### 3. Update the Config.IP_ADDRESS variable with your IP

```bash
class Config {
  // Replace with your actual machine IP (e.g., '192.168.1.5')
  static const String IP_ADDRESS = "YOUR_LOCAL_IP_HERE";
}
```

### Setup and Run Frontend

```bash
cd sceneapp/
flutter pub get
flutter run -d <device_id>  # Use flutter devices for list of devices
```

---

## Features

- Upload a script and automatically extract characters and dialogues
- Assign who plays each character: You or AI
- Live camera recording while delivering lines
- AI Text-to-Speech for characters assigned to AI
- Real-time Speech-to-Text matching using Deepgram WebSocket API
- Expandable script panel for real-time reference
- Automatically saves recordings to device gallery
- Cross-platform Flutter UI (Android, iOS, Desktop)

---
