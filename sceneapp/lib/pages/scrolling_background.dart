import 'package:flutter/material.dart';

class ScrollingBackground extends StatefulWidget {
  final String imagePath; 
  final double scrollSpeed; 

  const ScrollingBackground({
    super.key, 
    required this.imagePath, 
    this.scrollSpeed = 30.0, 
  });

  @override
  State<ScrollingBackground> createState() => _ScrollingBackgroundState();
}

class _ScrollingBackgroundState extends State<ScrollingBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.scrollSpeed.toInt()),
    )..repeat(); 
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            // Image 1 (Top)
            Positioned(
              top: -1 * _controller.value * MediaQuery.of(context).size.height,
              height: MediaQuery.of(context).size.height,
              left: 0,
              right: 0,
              child: Image.asset(widget.imagePath, fit: BoxFit.cover),
            ),
            // Image 2 (Bottom - Following the first one)
            Positioned(
              top: MediaQuery.of(context).size.height - (_controller.value * MediaQuery.of(context).size.height),
              height: MediaQuery.of(context).size.height,
              left: 0,
              right: 0,
              child: Image.asset(widget.imagePath, fit: BoxFit.cover),
            ),
          ],
        );
      },
    );
  }
}