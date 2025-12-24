import 'package:flutter/material.dart';

class MyButton extends StatelessWidget {
  final Function()? onTap;
  final String text;      // Added this
  final Color? color;     // Kept this for custom colors

  const MyButton({
    super.key, 
    required this.onTap, 
    required this.text,   // Require text to be passed
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(25),
        margin: const EdgeInsets.symmetric(horizontal: 25),
        decoration: BoxDecoration(
          // Use passed color, or default to the Violet theme
          color: color ?? const Color(0xFF8A2BE2), 
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            text, // Use the variable text
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}