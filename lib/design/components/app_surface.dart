import 'package:flutter/material.dart';

/// A transparent Scaffold for routed pages.
///
/// The shell draws no opaque surface of its own — the paper canvas lives behind
/// everything — but routed pages still need a Material ancestor (ink, text
/// fields) and a ScaffoldMessenger host (snack bars). This provides both while
/// staying visually invisible.
class AppSurface extends StatelessWidget {
  const AppSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: child,
    );
  }
}
