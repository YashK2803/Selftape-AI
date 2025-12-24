import 'package:flutter/material.dart';
import 'package:sceneapp/pages/auth_page.dart'; // This acts as the "Traffic Cop"
import 'package:sceneapp/pages/login_page.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX: Robust initialization that ignores "Duplicate App" errors
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    // If Firebase is already initialized, we just print a note and continue.
    debugPrint("Firebase was already initialized: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      // Use AuthPage so logged-in users go straight to Home
      home: AuthPage(), 
    );
  }
}