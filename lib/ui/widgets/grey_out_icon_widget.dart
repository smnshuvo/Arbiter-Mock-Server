import 'package:flutter/material.dart';

class GreyOutIconWidget extends StatelessWidget {
  final String iconAssetPath;
  final double size;
  final double opacity;
  final double greyIntensity;

  const GreyOutIconWidget({
    super.key,
    required this.iconAssetPath,
    this.size = 100.0,
    this.opacity = 0.5,
    this.greyIntensity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix([
        0.2126 * greyIntensity, 0.7152 * greyIntensity, 0.0722 * greyIntensity, 0, 0,
        0.2126 * greyIntensity, 0.7152 * greyIntensity, 0.0722 * greyIntensity, 0, 0,
        0.2126 * greyIntensity, 0.7152 * greyIntensity, 0.0722 * greyIntensity, 0, 0,
        0, 0, 0, opacity, 0,
      ]),
      child: ClipOval(
        child: Image.asset(
          iconAssetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
