import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../components/text_field.dart';
import '../components/button.dart';
import '../components/square_tile.dart';
import 'signup_page.dart';
import 'home_page.dart';
import '../services/auth_service.dart';
import 'scrolling_background.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final Color primaryColor = const Color(0xFF8A2BE2);
  final Color backgroundColor = const Color(0xFF1E1E1E);

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  // --- NEW: State variable to handle loading safely ---
  bool _isLoading = false;
  bool _isPasswordVisible = false;

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
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // Helper to toggle loading state
  void setLoading(bool loading) {
    setState(() {
      _isLoading = loading;
    });
  }

  // --- 1. EMAIL/PASS SIGN IN ---
  void signUserIn() async {
    if (_isLoading) return; // Prevent double taps
    if (emailController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
      _showMessage("Please enter both email and password.", isError: true);
      return;
    }
    setLoading(true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      // No need to set loading false here, as we are navigating away
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (context) => const HomePage()));
      }
    } on FirebaseAuthException catch (e) {
      setLoading(false);
      _showMessage(e.code.replaceAll('-', ' '));
    }
  }

  // --- 2. SOCIAL SIGN IN LOGIC ---
  void socialSignIn(String provider) async {
    if (_isLoading) return; // Prevent double taps
    setLoading(true);

    try {
      UserCredential? userCredential;

      if (provider == 'google') {
        userCredential = await _authService.signInWithGoogle();
      } else if (provider == 'apple') {
        userCredential = await _authService.signInWithApple();
      }

      if (userCredential != null && mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (context) => const HomePage()));
      } else {
        // User canceled or failed
        setLoading(false);
      }
    } catch (e) {
      setLoading(false);
      _showMessage("Sign in failed. Please try again.");
    }
  }

void _showMessage(String message, {bool isError = false}) {
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
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      // Use Stack to put the Loader ON TOP of everything
      body: Stack(
        children: [
          // 1. Background Layer
          // ---------------------------------------------------------
          // 1. BACKGROUND LAYER (Infinite Scroll)
          // ---------------------------------------------------------
          const ScrollingBackground(
             // Make sure this image exists in your assets folder!
             imagePath: 'assets/images/collage.jpeg', 
             scrollSpeed: 40,
          ),

          // ---------------------------------------------------------
          // 2. DIMMER LAYER (Overlay)
          // ---------------------------------------------------------
          // This creates the dark tint so text is readable
          Container(
            color: Colors.black.withOpacity(0.75), 
          ),

          // 2. Main Content Layer
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: isSmallScreen ? 10 : 30),
                    const Icon(Icons.lock_outline, size: 50, color: Colors.white),
                    const SizedBox(height: 10),
                    const Text('SelfTape-AI',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 30),

                    MyTextField(
                      controller: emailController,
                      hintText: 'Email',
                      obscureText: false,
                    ),
                    const SizedBox(height: 10),
MyTextField(
                      controller: passwordController,
                      hintText: 'Password',
                      // Toggle this based on state
                      obscureText: !_isPasswordVisible, 
                      // Add the Eye Icon button
                      suffixIcon: IconButton(
                        icon: Icon(
                          // Choose icon based on state
                          _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          // Flip the state when clicked
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8.0, right: 5.0),
                        child: GestureDetector(
                          onTap: () async {
                             if (_isLoading) return;
                             if (emailController.text.isEmpty) {
                               _showMessage("Enter email to reset password.");
                               return;
                             }
                             try {
                               await _authService.sendPasswordResetEmail(emailController.text.trim());
                               _showMessage("Reset link sent!");
                             } catch (e) {
                               _showMessage("Error sending email.");
                             }
                          },
                          child: Text('Forgot Password?',
                              style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    MyButton(
                      onTap: signUserIn,
                      text: "Sign In",
                    ),
                    const SizedBox(height: 25),

                    // Divider
                    Row(
                      children: [
                        Expanded(child: Divider(thickness: 0.5, color: Colors.grey[600])),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10.0),
                            child: Text('Or', style: TextStyle(color: Colors.grey[400]))),
                        Expanded(child: Divider(thickness: 0.5, color: Colors.grey[600])),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Social Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => socialSignIn('google'),
                          child: Transform.scale(
                              scale: 0.8,
                              child: SquareTile(imagePath: 'lib/images/google.png')),
                        ),
                        const SizedBox(width: 20),
                        GestureDetector(
                          onTap: () => socialSignIn('apple'),
                          child: Transform.scale(
                              scale: 0.8,
                              child: SquareTile(imagePath: 'lib/images/apple.png')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Not a member?', style: TextStyle(color: Colors.grey[400])),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            if (!_isLoading) {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const SignUpPage()));
                            }
                          },
                          child: const Text('Register',
                              style: TextStyle(
                                  color: Color(0xFF8A2BE2), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Loading Overlay Layer (The Safe Fix)
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF8A2BE2)),
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
          shape: BoxShape.circle, color: primaryColor.withOpacity(opacity)),
    );
  }
}