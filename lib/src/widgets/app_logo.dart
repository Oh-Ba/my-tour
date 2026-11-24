import 'package:flutter/material.dart';

/// The logo: a traveller looking through a spyglass. The same drawing is the
/// launcher icon; both come from `tool/generate_logo.py`.
const String appLogoAsset = 'assets/logo.png';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.2),
      child: Image.asset(
        appLogoAsset,
        width: size,
        height: size,
        semanticLabel: 'My Tour',
      ),
    );
  }
}
