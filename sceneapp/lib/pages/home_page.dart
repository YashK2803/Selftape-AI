import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:sceneapp/pages/page_selection.dart'; // Ensure this exists
import 'package:sceneapp/ip_address.dart'; // Ensure this exists
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'login_page.dart'; // Needed for logout navigation
import 'package:sceneapp/services/storage_service.dart'; // Import service
import 'package:share_plus/share_plus.dart'; // Import share
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  // --- VARIABLES ---
  int _selectedIndex = 0;
  String? fileName;
  String? filePath;
  List<CameraDescription>? cameras;
  bool _loadingCameras = true;
  List<Map<String, dynamic>> _historyData = [];

  final Color primaryColor = const Color(0xFF8A2BE2);
  final Color backgroundColor = const Color(0xFF1E1E1E);
  final AuthService _authService = AuthService();
  final StorageService _storageService = StorageService();

  // Animation stuff
  late AnimationController _rippleController;
  late Animation<double> _ripple1, _ripple2;

  @override
  void initState() {
    super.initState();
    _initCameras();
    _loadHistory();
    
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

  // --- GENERAL HELPERS ---
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> historyList = prefs.getStringList('video_history') ?? [];
    setState(() {
      _historyData = historyList
          .map((e) => jsonDecode(e) as Map<String, dynamic>)
          .toList()
          .reversed
          .toList();
    });
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('video_history');
    _loadHistory();
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

  void signUserOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  // --- PROFILE ACTIONS ---

  // 1. Change Username
  void _showChangeUsernameDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final controller = TextEditingController(text: user?.displayName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Change Username", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Enter new username",
            hintStyle: TextStyle(color: Colors.grey[500]),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await user?.updateDisplayName(controller.text.trim());
                await user?.reload();
                setState(() {}); // Refresh UI
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Username updated!")),
                );
              }
            },
            child: Text("Save", style: TextStyle(color: primaryColor)),
          ),
        ],
      ),
    );
  }

  // 2. Change Password
  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Change Password", style: TextStyle(color: Colors.white)),
        content: const Text(
          "We will send a password reset link to your email address. You can use it to set a new password.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user?.email != null) {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Reset email sent! Check your inbox.")),
                );
              }
            },
            child: Text("Send Email", style: TextStyle(color: primaryColor)),
          ),
        ],
      ),
    );
  }

  // 3. Delete Account
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Delete Account", style: TextStyle(color: Colors.redAccent)),
        content: const Text(
          "Are you sure? This action cannot be undone. All your data will be lost.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FirebaseAuth.instance.currentUser?.delete();
                // If successful, navigate to login
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context, 
                    MaterialPageRoute(builder: (context) => const LoginPage()), 
                    (route) => false
                  );
                }
              } on FirebaseAuthException catch (e) {
                if (mounted) Navigator.pop(context);
                if (e.code == 'requires-recent-login') {
                   ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Security: Please Log Out and Log In again to delete account.")),
                  );
                } else {
                   ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: ${e.message}")),
                  );
                }
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 4. About App
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("About SelfTapeAI", style: TextStyle(color: Colors.white)),
        content: const Text(
          "SelfTapeAI helps actors practice scenes by reading the other lines for them using AI.\n\nVersion: 1.0.0\nDeveloped by Yash",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Close", style: TextStyle(color: primaryColor)),
          ),
        ],
      ),
    );
  }


  // --- MAIN CONTENT LOGIC ---
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload a PDF first.')));
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // ... PDF logic same as before ...
    // Keeping this concise for the example, logic remains unchanged from your previous code
     final countRequest = http.MultipartRequest(
      'POST',
      Uri.parse('http://${Config.IP_ADDRESS}:8000/get-page-count/'),
    );
    countRequest.files.add(await http.MultipartFile.fromPath('file', filePath!));

    try {
      final countResponse = await countRequest.send();
      final countBody = await countResponse.stream.bytesToString();

      if (countResponse.statusCode == 200) {
        final countData = jsonDecode(countBody);
        final totalPages = countData['page_count'];
        
         if (cameras != null && cameras!.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PageSelection(
                filePath: filePath!,
                fileName: fileName!,
                userUid: user.uid,
                cameras: cameras!,
                totalPages: totalPages,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $countBody")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }


  // --- TABS ---
  
  // 1. HOME TAB
  Widget _buildHomeTab() {
    final user = FirebaseAuth.instance.currentUser;
    String displayName = "User";
    if (user != null) {
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        displayName = user.displayName!.split(' ')[0];
      } else if (user.email != null) {
        displayName = user.email!.split('@')[0];
      }
    }

    return Stack(
      children: [
        Positioned(
          top: -60, left: -80,
          child: AnimatedBuilder(
            animation: _ripple1,
            builder: (_, __) => Transform.scale(scale: _ripple1.value, child: _buildRipple(250, 0.3)),
          ),
        ),
        Positioned(
          bottom: -50, right: -70,
          child: AnimatedBuilder(
            animation: _ripple2,
            builder: (_, __) => Transform.scale(scale: _ripple2.value, child: _buildRipple(200, 0.3)),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 70, bottom: 24, left: 24, right: 24),
              child: Column(
                children: [
                  const Icon(Icons.description, size: 80, color: Colors.white),
                  const SizedBox(height: 10),
                  Text(
                    'Hello, $displayName 👋',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const SizedBox(height: 30),
                  Card(
                    color: Colors.grey[800],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: pickPdfFile,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Upload PDF'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[900],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Please upload PDFs with 20 or fewer pages.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          if (fileName != null) ...[
                            const SizedBox(height: 10),
                            Text('📄 $fileName', style: const TextStyle(color: Colors.white)),
                          ],
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: convertToText,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFFDA44bb), Color(0xFF8921aa)]),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3))],
                              ),
                              child: const Center(
                                child: Text('Proceed with Recording', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
    );
  }

  // 2. HISTORY TAB
 Widget _buildHistoryTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Please login"));

    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 120, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("Your Cloud Tapes", 
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _storageService.getRecordingsStream(user.uid),
              builder: (context, snapshot) {
                // 1. Loading State
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // 2. Empty State
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No recordings in the cloud yet.", 
                      style: TextStyle(color: Colors.grey)));
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final docId = docs[index].id;
                    final fileName = data['fileName'] ?? 'Unknown';
                    final downloadUrl = data['downloadUrl'] ?? '';
                    final storagePath = data['storagePath'] ?? '';

                    return FutureBuilder<bool>(
                      // Check if file exists locally
                      future: _checkLocalFile(fileName),
                      builder: (context, localSnapshot) {
                        bool isDownloaded = localSnapshot.data ?? false;

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: Colors.grey[900],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isDownloaded ? Colors.green.withOpacity(0.2) : primaryColor.withOpacity(0.2), 
                                shape: BoxShape.circle
                              ),
                              child: Icon(
                                isDownloaded ? Icons.check : Icons.cloud_download, 
                                color: isDownloaded ? Colors.green : Colors.white
                              ),
                            ),
                            title: Text(fileName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text(isDownloaded ? "On Device" : "In Cloud", 
                                style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            
                            // THREE DOT MENU
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.white70),
                              color: Colors.grey[850],
                              onSelected: (value) => _handleMenuAction(value, docId, storagePath, downloadUrl, fileName, isDownloaded),
                              itemBuilder: (context) => [
                                if (!isDownloaded)
                                  const PopupMenuItem(value: 'download', child: Text('Download', style: TextStyle(color: Colors.white))),
                                const PopupMenuItem(value: 'share', child: Text('Share', style: TextStyle(color: Colors.white))),
                                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                              ],
                            ),
                            onTap: () {
                              if (isDownloaded) {
                                // TODO: Play video logic here using local path
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Playing local video...")));
                              } else {
                                _downloadFile(downloadUrl, fileName);
                              }
                            },
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPER FUNCTIONS FOR HISTORY ---

  Future<bool> _checkLocalFile(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    return await file.exists();
  }

  Future<void> _downloadFile(String url, String fileName) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Downloading...")));
    try {
      await _storageService.downloadVideo(url, fileName);
      setState(() {}); // Refresh UI to show Green Check
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Complete!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _handleMenuAction(String action, String docId, String storagePath, String url, String fileName, bool isDownloaded) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (action == 'download') {
      _downloadFile(url, fileName);
    } 
    else if (action == 'share') {
      if (isDownloaded) {
        // Share Local File
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/$fileName';
        await Share.shareXFiles([XFile(path)], text: "Check out my SelfTape!");
      } else {
        // Share Cloud Link
        await Share.share("Watch my SelfTape here: $url");
      }
    } 
    else if (action == 'delete') {
      // Confirm Dialog
      bool confirm = await showDialog(
        context: context, 
        builder: (c) => AlertDialog(
          title: const Text("Delete Recording?"),
          content: const Text("This will delete it from the cloud and your device."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
          ],
        )
      ) ?? false;

      if (confirm) {
        // 1. Delete Cloud
        await _storageService.deleteVideo(docId, storagePath);
        await _storageService.deleteFirestoreDoc(user.uid, docId);
        
        // 2. Delete Local (Optional cleanup)
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        if (await file.exists()) {
          await file.delete();
        }
        
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted.")));
      }
    }
  }
// 3. PROFILE TAB (FIXED OVERFLOW)
  Widget _buildProfileTab() {
    final user = FirebaseAuth.instance.currentUser;
    return SafeArea(
      // FIX: Wrap in SingleChildScrollView to prevent bottom overflow
      child: SingleChildScrollView(
        // Moved padding here to ensure scrolling works for the whole area
        padding: const EdgeInsets.only(top: 70, left: 24, right: 24, bottom: 30),
        child: Column(
          children: [
            // Profile Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: primaryColor, width: 2),
              ),
              child: const Icon(Icons.person, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 15),
            Text(
               user?.displayName ?? user?.email ?? "User",
               style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
               textAlign: TextAlign.center,
            ),
            Text(
               user?.email ?? "",
               style: const TextStyle(color: Colors.grey, fontSize: 14)
            ),
            const SizedBox(height: 40),

            // Options List
            _buildProfileOption(Icons.info_outline, "About SelfTapeAI", _showAboutDialog),
            _buildProfileOption(Icons.edit, "Change Username", _showChangeUsernameDialog),
            _buildProfileOption(Icons.lock_reset, "Change Password", _showChangePasswordDialog),
            _buildProfileOption(Icons.delete_forever, "Delete Account", _showDeleteAccountDialog, isDestructive: true),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: isDestructive ? Colors.redAccent : Colors.white70),
        title: Text(title, style: TextStyle(color: isDestructive ? Colors.redAccent : Colors.white)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  Widget _buildRipple(double size, double opacity) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: primaryColor.withOpacity(opacity)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCameras) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    Widget bodyContent;
    if (_selectedIndex == 0) {
      bodyContent = _buildHomeTab();
    } else if (_selectedIndex == 1) {
      bodyContent = _buildHistoryTab();
    } else {
      bodyContent = _buildProfileTab();
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: true,
      
      // Top Header
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          padding: const EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 10),
          decoration: BoxDecoration(
             color: backgroundColor.withOpacity(0.95), 
             borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SelfTape-AI', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              IconButton(onPressed: signUserOut, icon: const Icon(Icons.logout, color: Colors.white)),
            ],
          ),
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: backgroundColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.white54,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
            if (index == 1) _loadHistory();
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      body: bodyContent,
    );
  }
}