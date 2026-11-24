import 'package:flutter/material.dart';

import 'app_logo.dart';

/// The mark that this build is the developer's own.
class DevBadge extends StatelessWidget {
  const DevBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'DEV',
      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, letterSpacing: 1),
    );
  }
}

/// The logo and name of the app; in developer mode, with DEV in red.
class AppTitle extends StatelessWidget {
  const AppTitle({super.key, required this.devMode});

  final bool devMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppLogo(),
        const SizedBox(width: 8),
        Text(
          'My Tour',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (devMode) ...[const SizedBox(width: 8), const DevBadge()],
      ],
    );
  }
}
