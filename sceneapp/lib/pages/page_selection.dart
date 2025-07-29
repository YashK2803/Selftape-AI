import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:sceneapp/pages/character_selection_page.dart';
import 'package:sceneapp/ip_address.dart';

class PageSelection extends StatefulWidget {
  final String filePath;
  final String fileName;
  final String userUid;
  final List<CameraDescription> cameras;
  final int totalPages;

  const PageSelection({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.userUid,
    required this.cameras,
    required this.totalPages,
  });

  @override
  State<PageSelection> createState() => _PageSelectionState();
}

class _PageSelectionState extends State<PageSelection>
    with SingleTickerProviderStateMixin {
  int? totalPages;
  Set<int> selectedPages = {};
  bool isLoading = true;
  bool isProcessing = false;
  bool selectAll = false;

  final Color primaryColor = const Color(0xFF8A2BE2); // Violet
  final Color backgroundColor = const Color(0xFF1E1E1E); // Dark grey

  late AnimationController _rippleController;
  late Animation<double> _ripple1, _ripple2;

  @override
  void initState() {
    super.initState();
    _getPageCount();
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

  Future<void> _getPageCount() async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://${Config.IP_ADDRESS}:8000/get-page-count/'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', widget.filePath));

      var response = await request.send();
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        final responseJson = jsonDecode(responseBody);
        setState(() {
          totalPages = responseJson['page_count'];
          isLoading = false;
        });
      } else {
        _showError('Failed to get page count');
      }
    } catch (e) {
      _showError('Failed to connect to backend');
    }
  }

  void _showError(String message) {
    setState(() {
      isLoading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _toggleSelectAll() {
    setState(() {
      selectAll = !selectAll;
      if (selectAll) {
        // Select pages 1 to totalPages (the actual number of pages in the PDF)
        selectedPages = Set<int>.from(List.generate(totalPages!, (index) => index + 1));
      } else {
        selectedPages.clear();
      }
    });
  }

  void _togglePageSelection(int page) {
    setState(() {
      if (selectedPages.contains(page)) {
        selectedPages.remove(page);
        selectAll = false;
      } else {
        selectedPages.add(page);
        // Check if all pages are now selected
        if (selectedPages.length == totalPages) {
          selectAll = true;
        }
      }
    });
  }

Future<void> _processSelectedPages() async {
  if (selectedPages.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select at least one page.')),
    );
    return;
  }

  setState(() {
    isProcessing = true;
  });

  // Step 1: Check page count
  var countRequest = http.MultipartRequest(
    'POST',
    Uri.parse('http://${Config.IP_ADDRESS}:8000/get-page-count/'),
  );
  countRequest.files.add(await http.MultipartFile.fromPath('file', widget.filePath));

  try {
    var countResponse = await countRequest.send();
    final countBody = await countResponse.stream.bytesToString();

    if (countResponse.statusCode == 400) {
      final decoded = jsonDecode(countBody);
      final errorMessage = decoded['detail'] ?? "Invalid PDF.";

      if (mounted) {
        setState(() => isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
        // ✅ Correct redirection
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
      return;
    } else if (countResponse.statusCode != 200) {
      if (mounted) {
        setState(() => isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error checking page count: $countBody")),
        );
      }
      return;
    }
  } catch (e) {
    if (mounted) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to verify PDF page count.")),
      );
    }
    return;
  }

  // Step 2: Upload selected pages
  List<int> zeroIndexedPages = selectedPages.map((page) => page - 1).toList();
  zeroIndexedPages.sort();

  var request = http.MultipartRequest(
    'POST',
    Uri.parse('http://${Config.IP_ADDRESS}:8000/upload-pdf-with-pages/'),
  );
  request.fields['user_uid'] = widget.userUid;
  request.fields['page_numbers'] = jsonEncode(zeroIndexedPages);
  request.files.add(await http.MultipartFile.fromPath('file', widget.filePath));

  try {
    var response = await request.send();
    if (response.statusCode == 200) {
      final responseBody = await response.stream.bytesToString();
      final responseJson = jsonDecode(responseBody);

      final text = responseJson['text'].toString().replaceAll('\n', '\n');
      final characters = List<String>.from(responseJson['characters']);
      final scriptHash = responseJson['script_hash'].toString();
      final userUid = responseJson['user_uid'].toString();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => CharacterSelectionPage(
              extractedText: text,
              cameras: widget.cameras,
              characters: characters,
              scriptHash: scriptHash,
              userUid: userUid,
            ),
          ),
        );
      }

      return; // Optional but clean
    } else {
      if (mounted) {
        setState(() => isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${response.statusCode}')),
        );
      }
    }
  } catch (e) {
    if (mounted) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect to backend.')),
      );
    }
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background ripples
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

          // Header
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
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Pages',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Choose pages to extract',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF8A2BE2)),
                        SizedBox(height: 20),
                        Text(
                          'Analyzing PDF...',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      const SizedBox(height: 120), // Space for header
                      
                      // File info and select all
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Card(
                          color: Colors.grey[800],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.description, 
                                         color: Colors.white, size: 24),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        widget.fileName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Total Pages: $totalPages',
                                  style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Selected: ${selectedPages.length}',
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _toggleSelectAll,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: selectAll ? primaryColor : Colors.transparent,
                                          border: Border.all(color: primaryColor),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          selectAll ? 'Deselect All' : 'Select All',
                                          style: TextStyle(
                                            color: selectAll ? Colors.white : primaryColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Page grid - Limited by totalPages (number of pages in PDF)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.8,
                            ),
                            itemCount: totalPages, // This ensures upper limit is PDF page count
                            itemBuilder: (context, index) {
                              final pageNumber = index + 1; // Pages numbered 1 to totalPages
                              final isSelected = selectedPages.contains(pageNumber);
                              
                              return GestureDetector(
                                onTap: () => _togglePageSelection(pageNumber),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? primaryColor : Colors.grey[800],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? primaryColor : Colors.grey[600]!,
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.description,
                                        color: isSelected ? Colors.white : Colors.grey[400],
                                        size: 30,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '$pageNumber',
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.grey[300],
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // Process button
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: GestureDetector(
                          onTap: isProcessing ? null : _processSelectedPages,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              gradient: isProcessing
                                  ? LinearGradient(
                                      colors: [Colors.grey[600]!, Colors.grey[700]!],
                                    )
                                  : const LinearGradient(
                                      colors: [Color(0xFFDA44bb), Color(0xFF8921aa)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 6,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Center(
                              child: isProcessing
                                  ? const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Processing...',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Continue with Selected Pages',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
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