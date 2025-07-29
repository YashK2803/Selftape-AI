import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:sceneapp/pages/character_selection_page.dart';
import 'package:sceneapp/ip_address.dart';
import 'package:sceneapp/pages/page_selection.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  String? fileName;
  String? filePath;
  List<CameraDescription>? cameras;
  bool _loadingCameras = true;

  // final Color primaryColor = const Color(0xFFFFA69E);
  final Color primaryColor = const Color(0xFF8A2BE2); // Violet
  final Color backgroundColor = const Color(0xFF1E1E1E); // Dark grey

  late AnimationController _rippleController;
  late Animation<double> _ripple1, _ripple2;

  @override
  void initState() {
    super.initState();
    _initCameras();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _ripple1 = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeInOut),
    );

    _ripple2 = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _rippleController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  Future<void> _initCameras() async {
    try {
      final cams = await availableCameras();
      setState(() {
        cameras = cams;
        _loadingCameras = false;
      });
    } catch (e) {
      setState(() {
        cameras = [];
        _loadingCameras = false;
      });
    }
  }

  void signUserOut() => FirebaseAuth.instance.signOut();

  Future<void> pickPdfFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      setState(() {
        fileName = file.name;
        filePath = file.path;
      });
    }
  }

  Future<void> convertToText() async {
  if (filePath == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please upload a PDF first.')),
    );
    return;
  }

  final user = FirebaseAuth.instance.currentUser;
  final userUid = user?.uid;

  if (userUid == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You must be logged in.')),
    );
    return;
  }

  // ✅ Check page count BEFORE navigating
  final countRequest = http.MultipartRequest(
    'POST',
    Uri.parse('http://${Config.IP_ADDRESS}:8000/get-page-count/'),
  );
  countRequest.files.add(await http.MultipartFile.fromPath('file', filePath!));

  try {
    final countResponse = await countRequest.send();
    final countBody = await countResponse.stream.bytesToString();

    if (countResponse.statusCode == 400) {
      final decoded = jsonDecode(countBody);
      final errorMessage = decoded['detail'] ?? "PDF is too long.";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      return;
    } else if (countResponse.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $countBody")),
      );
      return;
    }

    // ✅ Success: proceed
    final countData = jsonDecode(countBody);
    final totalPages = countData['page_count'];

    if (cameras != null && cameras!.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PageSelection(
            filePath: filePath!,
            fileName: fileName!,
            userUid: userUid,
            cameras: cameras!,
            totalPages: totalPages,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not available.')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to check PDF page count.')),
    );
  }
}



  @override
  Widget build(BuildContext context) {
    if (_loadingCameras) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: backgroundColor,

      extendBodyBehindAppBar: true,

      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: backgroundColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.white,
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        onTap: (index) {},
      ),

      body: Stack(
        children: [
          Positioned(
            top: -60,
            left: -80,
            child: AnimatedBuilder(
              animation: _ripple1,
              builder: (context, child) => Transform.scale(
                scale: _ripple1.value,
                child: _buildRipple(250, 0.3),
              ),
            ),
          ),
          Positioned(
            top: -60,
            left: -80,
            child: AnimatedBuilder(
              animation: _ripple1,
              builder: (context, child) => Transform.scale(
                scale: _ripple1.value,
                child: _buildRipple(300, 0.3),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -70,
            child: AnimatedBuilder(
              animation: _ripple2,
              builder: (context, child) => Transform.scale(
                scale: _ripple2.value,
                child: _buildRipple(150, 0.3),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -70,
            child: AnimatedBuilder(
              animation: _ripple2,
              builder: (context, child) => Transform.scale(
                scale: _ripple2.value,
                child: _buildRipple(200, 0.3),
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.only(
                top: 50,
                bottom: 20,
                left: 20,
                right: 20,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SelfTape-AI',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Lights. Camera. Record!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: signUserOut,
                    icon: const Icon(Icons.logout, color: Colors.white),
                    tooltip: 'Logout',
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  top: 130,
                  bottom: 24,
                  left: 24,
                  right: 24,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.description,
                      size: 80,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hello, ${user?.email ?? 'User'} 👋',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Card(
                      color: Colors.grey[800],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 5,
                      shadowColor: Colors.black12,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 30,
                          horizontal: 20,
                        ),
                        child: Column(
                          children: [
                        ElevatedButton.icon(
                          onPressed: pickPdfFile,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload PDF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[900],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 24,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: Text(
                            'Please upload PDFs with 10 or fewer pages.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (fileName != null)
                          Text(
                            '📄 $fileName',
                            style: TextStyle(color: Colors.white),
                          ),
                        const SizedBox(height: 10),

                            // ElevatedButton(
                            //   onPressed: convertToText,
                            //   style: ElevatedButton.styleFrom(
                            //     backgroundColor: primaryColor,
                            //     foregroundColor: Colors.white,
                            //     padding: const EdgeInsets.symmetric(
                            //       vertical: 14,
                            //       horizontal: 24,
                            //     ),
                            //     textStyle: const TextStyle(fontSize: 16),
                            //     shape: RoundedRectangleBorder(
                            //       borderRadius: BorderRadius.circular(12),
                            //     ),
                            //   ),
                            //   child: const Text('Proceed with Recording'),
                            // ),

                            GestureDetector(
                              onTap: convertToText,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFDA44bb), Color(0xFF8921aa)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black45,
                                      blurRadius: 6,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    'Proceed with Recording',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRipple(double size, double opacity) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primaryColor.withOpacity(opacity),
      ),
    );
  }
}