import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/text_field.dart';
import '../components/button.dart';
import '../components/square_tile.dart';
import 'home_page.dart';
import 'scrolling_background.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> with SingleTickerProviderStateMixin {
  final Color primaryColor = const Color(0xFF8A2BE2);
  final Color backgroundColor = const Color(0xFF1E1E1E);

  // Controllers
  final usernameController = TextEditingController(); // Added
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  late AnimationController _rippleController;
  late Animation<double> _ripple1, _ripple2;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _ripple1 = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeInOut),
    );

    _ripple2 = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _rippleController, curve: const Interval(0.5, 1.0, curve: Curves.easeInOut)),
    );
  }

  @override
  void dispose() {
    _rippleController.dispose();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

void signUserUp() async {
  if (usernameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty ||
        confirmPasswordController.text.trim().isEmpty) {
      _showErrorMessage("Please fill in all fields.", isError: true);
      return;
    }
    // Show loading circle
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF8A2BE2)),
      ),
    );

    // Try creating the user
    try {
      // Check passwords match
      if (passwordController.text != confirmPasswordController.text) {
        Navigator.pop(context);
        _showErrorMessage("Passwords don't match!");
        return;
      }

      // 1. Create User
      UserCredential userCredential = 
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      // 2. SAVE USERNAME (Update Display Name)
      if (userCredential.user != null) {
        await userCredential.user!.updateDisplayName(usernameController.text.trim());
        await userCredential.user!.reload(); // Refresh to make sure it sticks
      }

      // Pop loading circle
      if (mounted) Navigator.pop(context);

      // Navigate to Home
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorMessage(e.code.replaceAll('-', ' '));
    }
  }

 void _showErrorMessage(String message, {bool isError = false}) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent, // Make background transparent for custom shape
          insetPadding: const EdgeInsets.all(20), // Adds margin from screen edges
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2C), // Slightly lighter dark grey for contrast
              borderRadius: BorderRadius.circular(20), // Smooth rounded corners
              border: Border.all(
                color: isError ? Colors.redAccent.withOpacity(0.5) : const Color(0xFF8A2BE2).withOpacity(0.5), 
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Wrap content height
              children: [
                // 1. Optional Icon for visual punch
                // Icon(
                //   isError ? Icons.warning_amber_rounded : Icons.mark_email_read_rounded,
                //   color: isError ? Colors.redAccent : const Color(0xFF8A2BE2),
                //   size: 48,
                // ),
                // const SizedBox(height: 16),

                // 2. The Title (Optional, you can remove if just passing message)
                Text(
                  "Oops!",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // 3. The Actual Message
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 15,
                    height: 1.4, // Better readability
                  ),
                ),
                const SizedBox(height: 24),

                // 4. The Action Button
                SizedBox(
                  width: double.infinity, // Full width button
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A2BE2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "OK",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
// ---------------------------------------------------------
          // 1. BACKGROUND LAYER (Infinite Scroll)
          // ---------------------------------------------------------
          const ScrollingBackground(
             imagePath: 'assets/images/collage.jpeg', 
             scrollSpeed: 40,
          ),

          // ---------------------------------------------------------
          // 2. DIMMER LAYER (Overlay)
          // ---------------------------------------------------------
          Container(
            color: Colors.black.withOpacity(0.75), 
          ),

          // --- MAIN CONTENT ---
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 10),
                    const Icon(Icons.person_add_alt_1, size: 50, color: Colors.white), // Compact Icon
                    const SizedBox(height: 10),
                    const Text(
                      'Create Account',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    // Compact Inputs
                    MyTextField(
                      controller: usernameController,
                      hintText: 'Username',
                      obscureText: false,
                    ),
                    const SizedBox(height: 10),

                    MyTextField(
                      controller: emailController,
                      hintText: 'Email',
                      obscureText: false,
                    ),
                    const SizedBox(height: 10),

// Password (UPDATED)
                MyTextField(
                  controller: passwordController,
                  hintText: 'Password',
                  obscureText: !_isPasswordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // Confirm Password (UPDATED)
                MyTextField(
                  controller: confirmPasswordController,
                  hintText: 'Confirm Password',
                  obscureText: !_isConfirmPasswordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                      });
                    },
                  ),
                ),
                    const SizedBox(height: 20),

                    // Sign Up Button
                    MyButton(
                      onTap: signUserUp,
                      text: "Sign Up",
                    ),
                    const SizedBox(height: 20),

                    // Login Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Have an account?', style: TextStyle(color: Colors.grey[400])),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text(
                            'Login',
                            style: TextStyle(color: Color(0xFF8A2BE2), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
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

  Widget _buildRipple(double size, double opacity) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: primaryColor.withOpacity(opacity)),
    );
  }
}