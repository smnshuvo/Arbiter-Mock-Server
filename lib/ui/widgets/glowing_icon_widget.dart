import 'package:flutter/material.dart';

class GlowingIconWidget extends StatefulWidget {
  final String iconAssetPath;
  final double size;
  final Color glowColor;

  const GlowingIconWidget({
    super.key,
    required this.iconAssetPath,
    this.size = 100.0,
    this.glowColor = Colors.blue,
  });

  @override
  State<GlowingIconWidget> createState() => _GlowingIconWidgetState();
}

class _GlowingIconWidgetState extends State<GlowingIconWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(_animation.value * 0.6),
                blurRadius: 20 + (_animation.value * 30),
                spreadRadius: 5 + (_animation.value * 10),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              widget.iconAssetPath,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}