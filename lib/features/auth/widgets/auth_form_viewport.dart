import 'package:flutter/material.dart';

/// Keeps authentication forms centered while allowing short windows to scroll.
class AuthFormViewport extends StatelessWidget {
  final Widget child;

  const AuthFormViewport({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: child,
        ),
      ),
    );
  }
}
