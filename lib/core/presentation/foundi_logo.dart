import 'package:flutter/material.dart';

class FoundiLogo extends StatelessWidget {
  const FoundiLogo({super.key, this.size = 32, this.decorative = false});
  final double size;
  final bool decorative;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: Image.asset(
      'assets/branding/foundi-mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: decorative ? null : 'Logo Foundi',
      excludeFromSemantics: decorative,
    ),
  );
}
