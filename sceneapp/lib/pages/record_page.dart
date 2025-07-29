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
  bool _isPlayerInited = false;
  bool _isPlaying = false;

  CameraController? _controller;
  bool _isRecording = false;
  IOWebSocketChannel? _channel;
  late stt.SpeechToText _speech;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initCamera();
    _initPlayer();
    _initPermissions();
  }

  void _initPlayer() async {
    try {
      await Permission.microphone.request();
      await _player.openPlayer();

      // Set up player subscription to track playback state
      _player.onProgress!.listen((e) {
        // Handle progress if needed
      });

      setState(() {
        _isPlayerInited = true;
      });
      debugPrint('[Player] Initialized successfully');
    } catch (e) {
      debugPrint('[Player Init Error]: $e');
    }
  }

  void _initPermissions() async {
    await Permission.microphone.request();
    await Permission.camera.request();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      return;
    }

    final frontCamera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.max,
      enableAudio: false,
    );

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
    debugPrint('[STT] Initializing speech recognition...');
    
    bool available = await _speech.initialize();
    if (available) {
      debugPrint('[STT] Mic initialized. Listening for user speech...');
      
      _speech.listen(
        onResult: (val) {
          if (val.finalResult && val.recognizedWords.isNotEmpty) {
            final transcript = val.recognizedWords;
            debugPrint('[STT] Final recognized line: "$transcript"');
            
            if (_channel != null) {
              final payload = jsonEncode({"transcript": transcript});
              _channel!.sink.add(payload);
              debugPrint('[STT Sent]: $payload');
            } else {
              debugPrint('[STT] WebSocket channel not connected');
            }
          } else {
            debugPrint('[STT] Partial or empty result received');
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 15),
        partialResults: false,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      );

      debugPrint('[STT] Now actively listening...');
    } else {
      debugPrint('[STT] Speech recognition not available');
    }
  }

  void _stopListening() {
    if (_speech.isListening) {
      _speech.stop();
      debugPrint('[STT] Stopped listening');
    }
  }

  Future<void> _playAudioFromBytes(List<int> audioBytes) async {
    debugPrint('[PLAYER] _playAudioFromBytes called with ${audioBytes.length} bytes');

    if (!_isPlayerInited) {
      debugPrint('[Player] Not initialized');
      return;
    }

    if (_isPlaying) {
      debugPrint('[Player] Already playing, stopping current playback');
      await _player.stopPlayer();
      _isPlaying = false;
    }

    try {
      debugPrint('[Player] Starting playback of ${audioBytes.length} bytes');

      // Stop listening while AI is speaking
      _stopListening();
      debugPrint('[STT] Mic stopped for AI playback');
      setState(() {
        _isPlaying = true;
      });

      await _player.startPlayer(
        fromDataBuffer: Uint8List.fromList(audioBytes),
        codec: Codec.pcm16,
        sampleRate: 16000,
        numChannels: 1,
        whenFinished: () {
          debugPrint('[Player] Playback finished');
          setState(() {
            _isPlaying = false;
          });

          if (_channel != null) {
            _channel!.sink.add(jsonEncode({"done": true}));
            debugPrint('[WS] Sent playback done ack');
          }

          if (_isRecording) {
            debugPrint('[STT] Mic restarted after AI line');
            _startListening();
          }
        },
      );

      debugPrint('[Player] Audio playback started successfully');
    } catch (e, st) {
      debugPrint('[Player Error]: $e\n$st');
      setState(() {
        _isPlaying = false;
      });
      // Resume listening even if playback failed
      if (_isRecording) {
        _startListening();
      }
    }
  }

  // Future<void> _startScriptDialogueWebSocket() async {
  //   try {
  //     final uri = Uri.parse('ws://${Config.IP_ADDRESS}:8000/ws-dialogue/');
  //     _channel = IOWebSocketChannel.connect(uri);

  //     _channel!.stream.listen(
  //       (message) async {
  //         try {
  //           debugPrint(
  //             '[WS Response]: Received message of type ${message.runtimeType}',
  //           );

  //           if (message is String) {
  //             try {
  //               final decoded = json.decode(message);
  //               if (decoded is Map && decoded.containsKey("tts_text")) {
  //                 debugPrint('[TTS Line]: ${decoded["tts_text"]}');
  //               }
  //             } catch (_) {
  //               debugPrint('[WS Text]: $message');
  //             }
  //           } else if (message is List<int>) {
  //             debugPrint('[WS Binary Audio]: Received ${message.length} bytes');
  //             await _playAudioFromBytes(message);
  //           } else if (message is Uint8List) {
  //             debugPrint(
  //               '[WS Uint8List Audio]: Received ${message.length} bytes',
  //             );
  //             await _playAudioFromBytes(message.toList());
  //           }
  //         } catch (e, st) {
  //           debugPrint('[WS STREAM ERROR]: $e\n$st');
  //         }
  //       },
  //       onError: (error) {
  //         debugPrint('[WS Error]: $error');
  //       },
  //       onDone: () {
  //         debugPrint('[WS Closed]');
  //         if (_isRecording) {
  //           _startListening(); // Resume listening when connection closes
  //         }
  //       },
  //     );

  //     // Send initialization payload
  //     final initPayload = jsonEncode({
  //       "script": widget.extractedText,
  //       "user_roles": widget.userRole.split(",").map((e) => e.trim()).toList(),
  //       "ai_character_genders": widget.aiCharacters,
  //     });

  //     _channel!.sink.add(initPayload);
  //     debugPrint('🔥 Sent initPayload: $initPayload');

  //     // Start listening for speech after WebSocket is connected
  //     await Future.delayed(const Duration(milliseconds: 500));
  //   } catch (e) {
  //     debugPrint('[WS Init Error]: $e');
  //   }
  // }


  Future<void> _startScriptDialogueWebSocket() async {
  try {
    final uri = Uri.parse('ws://${Config.IP_ADDRESS}:8000/ws-dialogue/');
    _channel = IOWebSocketChannel.connect(uri);

    // Attach listener BEFORE sending anything
    _channel!.stream.listen(
      (message) async {
        try {
          debugPrint(
            '[WS Response]: Received message of type ${message.runtimeType}',
          );
          debugPrint('[RAW WS MESSAGE] $message');

          if (message is String) {
            try {
              final decoded = json.decode(message);

              // ✅ Handle TTS debug text
              if (decoded is Map && decoded.containsKey("tts_text")) {
                debugPrint('[TTS Line]: ${decoded["tts_text"]}');
              }

              // ✅ NEW: Restart mic if backend says it's the user's turn
              if (decoded is Map && decoded.containsKey("next_turn")) {
                if (decoded["next_turn"] == "user") {
                  debugPrint('[WS] Backend says it is now your turn. Restarting mic...');
                  _startListening();
                }
              }

            } catch (e) {
              debugPrint('[WS Text Decode Error]: $e\nRaw message: $message');
            }
          } else if (message is List<int>) {
            debugPrint('[WS Binary Audio]: Received ${message.length} bytes');
            await _playAudioFromBytes(message);
          } else if (message is Uint8List) {
            debugPrint(
              '[WS Uint8List Audio]: Received ${message.length} bytes',
            );
            await _playAudioFromBytes(message.toList());
          } else {
            debugPrint('[WS Unknown Type]: $message');
          }
        } catch (e, st) {
          debugPrint('[WS STREAM ERROR]: $e\n$st');
        }
      },
      onError: (error) {
        debugPrint('[WS Error]: $error');
      },
      onDone: () {
        debugPrint('[WS Closed]');
        if (_isRecording) {
          _startListening(); // Resume listening when connection closes
        }
      },
    );

    // Send initialization payload AFTER listener is ready
    final initPayload = jsonEncode({
      "script": widget.extractedText,
      "user_roles": widget.userRole.split(",").map((e) => e.trim()).toList(),
      "ai_character_genders": widget.aiCharacters,
    });

    _channel!.sink.add(initPayload);
    debugPrint('Sent initPayload: $initPayload');

    // Optional: small delay before starting STT (if needed)
    await Future.delayed(const Duration(milliseconds: 300));
  } catch (e) {
    debugPrint('[WS Init Error]: $e');
  }
}


  Future<void> _recordVideo() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      try {
        final XFile file = await _controller!.stopVideoRecording();
        setState(() => _isRecording = false);
        _stopListening();

        // Stop any ongoing playback
        if (_isPlaying) {
          await _player.stopPlayer();
          _isPlaying = false;
        }

        String videoPath = file.path;
        if (videoPath.endsWith('.temp')) {
          final newPath = videoPath.replaceAll('.temp', '.mp4');
          await File(videoPath).rename(newPath);
          videoPath = newPath;
        }

        final bool? success = await GallerySaver.saveVideo(videoPath);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success == true
                    ? 'Video saved to gallery!'
                    : 'Failed to save video.',
              ),
              backgroundColor: primaryColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        debugPrint('[Recording Stop Error]: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error stopping recording: $e'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      try {
        await _controller!.startVideoRecording();
        setState(() => _isRecording = true);
        await _startScriptDialogueWebSocket();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording started - AI dialogue ready'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        debugPrint('[Recording Start Error]: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error starting recording: $e'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _channel?.sink.close();
    _speech.stop();
    if (_isPlayerInited) {
      _player.closePlayer();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Container(
          decoration: BoxDecoration(
            color: bgcolor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'SelfTape-AI',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _isRecording ? 'Recording...' : 'Recording Mode',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          if (_isPlaying) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.volume_up,
                              size: 16,
                              color: Colors.black87,
                            ),
                            const Text(
                              ' AI Speaking',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Back',
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
              : CameraPreview(_controller!),

          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _recordVideo,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 60,
                  width: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : primaryColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.videocam,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.15,
            minChildSize: 0.1,
            maxChildSize: 0.8,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Text(
                      'Extracted Script',
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.extractedText,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_isRecording) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _speech.isListening ? Icons.mic : Icons.mic_off,
                              color: _speech.isListening
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _speech.isListening
                                  ? 'Listening for your speech...'
                                  : _isPlaying
                                  ? 'AI is speaking...'
                                  : 'Ready to listen',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
