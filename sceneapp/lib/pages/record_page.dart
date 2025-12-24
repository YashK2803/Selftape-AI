import 'dart:async'; // Added for Timer
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'dart:io';
import 'dart:convert';
import '../ip_address.dart';
import 'package:web_socket_channel/io.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sceneapp/pages/home_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sceneapp/services/storage_service.dart'; 
import 'package:audioplayers/audioplayers.dart';

class RecordingPage extends StatefulWidget {
  final String extractedText;
  final List<CameraDescription> cameras;
  final Map<String, String> aiCharacters;
  final String userRole;
  final String scriptHash;
  final String userUid;

  const RecordingPage({
    super.key,
    required this.extractedText,
    required this.cameras,
    required this.aiCharacters,
    required this.userRole,
    required this.scriptHash,
    required this.userUid,
  });

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  final Color primaryColor = const Color(0xFF8A2BE2);
  final Color bgcolor = const Color(0xFF1E1E1E);
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final TextEditingController _fileNameController = TextEditingController();
  final AudioPlayer _effectPlayer = AudioPlayer();
  // Inside _RecordingPageState class
bool _isMicActive = false; // <--- ADD THIS

  bool _isPlayerInited = false;
  bool _isPlaying = false;
  CameraController? _controller;
  bool _isRecording = false;
  IOWebSocketChannel? _channel;
  late stt.SpeechToText _speech;
  List<String> _scriptLines = [];
  int _currentLineIndex = 0;

  final StorageService _storageService = StorageService();
  bool _isUploading = false; 

  // --- Countdown State Variables ---
  bool _isCountingDown = false;
  int _countdownValue = 5;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _parseScriptLines();
    _initSpeech();
    _initCamera();
    _initPlayer();
    _initPermissions();
  }

  void _parseScriptLines() {
    if (widget.extractedText.isNotEmpty) {
      _scriptLines = widget.extractedText
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
    } else {
      _scriptLines = ["No script content available."];
    }
  }

  void _advanceScript() {
    if (_currentLineIndex < _scriptLines.length - 1) {
      setState(() {
        _currentLineIndex++;
      });
    } else {
      debugPrint("End of script reached. Wrapping up...");
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _isRecording) {
          _stopRecordingAndFinish(); 
        }
      });
    }
  }

  void _previousScriptLine() {
    if (_currentLineIndex > 0) {
      setState(() {
        _currentLineIndex--;
      });
    }
  }

  void _initPlayer() async {
    try {
      await Permission.microphone.request();
      await _player.openPlayer();
      setState(() => _isPlayerInited = true);
    } catch (e) {
      debugPrint('[Player Init Error]: $e');
    }
  }

  void _initPermissions() async {
    await Permission.microphone.request();
    await Permission.camera.request();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
    _controller = CameraController(frontCamera, ResolutionPreset.max, enableAudio: false);
    try {
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[Camera Init Error]: $e');
    }
  }

  void _initSpeech() {
    _speech = stt.SpeechToText();
  }

  Future<void> _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _isMicActive = true);
      _speech.listen(
        onResult: (val) {
          if (val.finalResult && val.recognizedWords.isNotEmpty) {
            final transcript = val.recognizedWords;
            debugPrint('[STT] Final recognized line: "$transcript"');

            _speech.cancel();
            setState(() => _isMicActive = false);

            if (_channel != null) {
              final payload = jsonEncode({"transcript": transcript});
              _channel!.sink.add(payload);
            }
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 15),
        listenMode: stt.ListenMode.search,
      );
    }
  }

  void _stopListening() {
    if (_speech.isListening) {
      _speech.stop();
    }
    if (mounted) setState(() => _isMicActive = false);
  }

  Future<void> saveRecordingToCloud(String videoFilePath, String customFileName) async {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be logged in to upload!")),
      );
      return;
    }

    setState(() {
      _isUploading = true; 
    });

    try {
      String finalName = "$customFileName.mp4";
      await _storageService.uploadVideo(videoFilePath, finalName, user.uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Upload Complete! 🎉")),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomePage()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload Failed: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _playAudioFromBytes(List<int> audioBytes) async {
    if (!_isPlayerInited) return;
    if (_isPlaying) {
      await _player.stopPlayer();
      _isPlaying = false;
    }

    try {
      setState(() => _isPlaying = true);

      await _player.startPlayer(
        fromDataBuffer: Uint8List.fromList(audioBytes),
        codec: Codec.pcm16,
        sampleRate: 16000,
        numChannels: 1,
        whenFinished: () {
          setState(() => _isPlaying = false);
          
          _advanceScript();

          if (_channel != null) {
            _channel!.sink.add(jsonEncode({"done": true}));
          }

          // if (_isRecording && _currentLineIndex < _scriptLines.length - 1) {
          //   _startListening();
          // }
        },
      );
    } catch (e) {
      setState(() => _isPlaying = false);
      if (_isRecording) _startListening();
    }
  }

  Future<void> _startScriptDialogueWebSocket() async {
    try {
      final uri = Uri.parse('ws://${Config.IP_ADDRESS}:8000/ws-dialogue/');
      _channel = IOWebSocketChannel.connect(uri);
      _channel!.stream.listen((message) async {
        try {
if (message is String) {
            final decoded = json.decode(message);
            
            // 1. === PLAY POSITIVE BEEP ===
            if (decoded is Map && decoded.containsKey("event") && decoded["event"] == "success") {
               // Make sure your file name matches exactly
               await _effectPlayer.play(AssetSource('sounds/positive_beep.mp3'));
            }

            // 2. === PLAY ERROR BEEP ===
            if (decoded is Map && decoded.containsKey("event") && decoded["event"] == "retry") {
               // Make sure your file name matches exactly
               await _effectPlayer.play(AssetSource('sounds/error_beep.mp3'));
            }

            // 3. Existing Logic (Keep this)
            if (decoded is Map && decoded.containsKey("next_turn") && decoded["next_turn"] == "user") {
               _startListening(); 
            }
            
            if (decoded is Map && decoded.containsKey("event") && decoded["event"] == "advance") {
               _advanceScript();
            }
          }else if (message is List<int>) {
            await _playAudioFromBytes(message);
          } else if (message is Uint8List) {
            await _playAudioFromBytes(message.toList());
          }
        } catch (e) {
          debugPrint('[WS Error]: $e');
        }
      });

      final initPayload = jsonEncode({
        "script": widget.extractedText,
        "user_roles": widget.userRole.split(",").map((e) => e.trim()).toList(),
        "ai_character_genders": widget.aiCharacters,
      });
      _channel!.sink.add(initPayload);
    } catch (e) {
      debugPrint('[WS Init Error]: $e');
    }
  }

  void _showSaveDialog(String videoPath) {
    _fileNameController.text = ""; 

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            "Recording Complete", 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Enter a name for this scene:", 
                style: TextStyle(color: Colors.white70)
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _fileNameController,
                autofocus: true, 
                style: const TextStyle(color: Colors.white),
                cursorColor: primaryColor,
                decoration: InputDecoration(
                  hintText: "e.g. Scene 1 - Take 1",
                  hintStyle: const TextStyle(color: Colors.white30),
                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: primaryColor)),
                ),
              ),
            ],
          ),
          actions: [
            // --- UPDATED CLOSE BUTTON ---
            TextButton(
              onPressed: () {
                // Navigate to HomePage
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomePage()),
                  (Route<dynamic> route) => false,
                ); 
              },
              child: const Text("Close", style: TextStyle(color: Colors.redAccent)),
            ),
            
            // SAVE BUTTON
            ElevatedButton(
              onPressed: () async {
                if (_fileNameController.text.trim().isNotEmpty) {
                  Navigator.of(context).pop(); 
                  await saveRecordingToCloud(videoPath, _fileNameController.text.trim());
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter a name first!"))
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor, 
                foregroundColor: Colors.white
              ),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  // --- RECORDING LOGIC WITH TIMER ---
  void _handleRecordButtonPress() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      // 1. If currently recording -> Stop everything
      _stopRecordingAndFinish();
    } else if (_isCountingDown) {
      // 2. If currently counting down -> Cancel countdown
      _cancelCountdown();
    } else {
      // 3. If idle -> Start Countdown Sequence
      _startCountdownSequence();
    }
  }

  void _startCountdownSequence() {
    setState(() {
      _isCountingDown = true;
      _countdownValue = 5;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownValue > 1) {
        setState(() {
          _countdownValue--;
        });
      } else {
        // Countdown finished (0)
        timer.cancel();
        setState(() {
          _isCountingDown = false;
        });
        _startActualRecording();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _isCountingDown = false;
      _countdownValue = 5;
    });
  }

  Future<void> _startActualRecording() async {
    try {
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
      // Start the script/AI flow only after recording starts
      await _startScriptDialogueWebSocket();
    } catch (e) {
      debugPrint('[Recording Start Error]: $e');
    }
  }

  Future<void> _stopRecordingAndFinish() async {
    try {
      final XFile file = await _controller!.stopVideoRecording();
      setState(() => _isRecording = false);
      _stopListening();
      if (_isPlaying) await _player.stopPlayer();

      String videoPath = file.path;
      if (videoPath.endsWith('.temp')) {
        final newPath = videoPath.replaceAll('.temp', '.mp4');
        await File(videoPath).rename(newPath);
        videoPath = newPath;
      }

      if (mounted) _showSaveDialog(videoPath);
    } catch (e) {
      debugPrint('[Recording Stop Error]: $e');
    }
  }

  Future<void> _recordVideo() async {
    _handleRecordButtonPress();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _channel?.sink.close();
    _speech.stop();
    _countdownTimer?.cancel(); 
    if (_isPlayerInited) _player.closePlayer();
    _fileNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String characterName = "";
    String dialogueText = "";
    if (_scriptLines.isNotEmpty) {
      final currentLine = _scriptLines[_currentLineIndex];
      final parts = currentLine.split(':');
      if (parts.length > 1) {
        characterName = parts[0].trim();
        dialogueText = parts.sublist(1).join(':').trim();
      } else {
        dialogueText = currentLine.trim();
      }
    } else {
      dialogueText = "No Lines";
    }

    Color characterColor = Colors.white;
    if (characterName.isNotEmpty) {
      final List<String> userRoles = widget.userRole.toUpperCase().split(',').map((e) => e.trim()).toList();
      if (userRoles.contains(characterName.toUpperCase())) {
        characterColor = Colors.greenAccent;
      } else {
        characterColor = Colors.redAccent;
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Container(
          decoration: BoxDecoration(color: bgcolor),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('SelfTape-AI', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                      SizedBox(height: 4),
                      Text('Lights. Camera. Record!', style: TextStyle(fontSize: 14, color: Colors.white, fontStyle: FontStyle.italic)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const HomePage()),
                        (Route<dynamic> route) => false,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          _controller == null || !_controller!.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : SizedBox.expand(child: CameraPreview(_controller!)),
          
          if (_isCountingDown)
            Container(
              color: Colors.black54, 
              child: Center(
                child: Text(
                  '$_countdownValue',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 120,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          Positioned(
            top: 20,
            right: 20,
            child: GestureDetector(
              onTap: _handleRecordButtonPress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 60,
                width: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording ? Colors.red : (_isCountingDown ? Colors.orangeAccent : primaryColor),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : (_isCountingDown ? Icons.close : Icons.videocam),
                  color: Colors.white, 
                  size: 28
                ),
              ),
            ),
          ),
          
          if (!_isCountingDown)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 30),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Icon(
                              // Check _isMicActive instead of _isRecording
                              _isPlaying ? Icons.volume_up : (_isMicActive ? Icons.mic : Icons.fiber_manual_record),
                              
                              // Update color logic
                              color: _isPlaying ? Colors.blueAccent : (_isMicActive ? Colors.redAccent : Colors.grey),
                              size: 16,
                            ),
                          const SizedBox(width: 8),
                            Text(
                                  // Update Text logic
                                  _isPlaying 
                                      ? "AI Speaking..." 
                                      : (_isMicActive ? "Listening..." : "Waiting for cue..."), 
                                  
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 20),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (characterName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                characterName,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: characterColor, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                              ),
                            ),
                          Text(
                            dialogueText,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: characterColor, fontSize: 20, fontWeight: FontWeight.w500, height: 1.4),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: Text("${_currentLineIndex + 1} / ${_scriptLines.length}", style: const TextStyle(color: Colors.white30, fontSize: 10)),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}