import 'package:flutter/material.dart';

/// A transparent Scaffold for routed pages.
///
/// The shell draws no opaque surface of its own — the paper canvas lives behind
/// everything — but routed pages still need a Material ancestor (ink, text
/// fields) and a ScaffoldMessenger host (snack bars). This provides both while
/// staying visually invisible.
///
/// It is hit-test opaque on purpose. Every [PageRoute] carries a colourless,
/// non-dismissible [ModalBarrier] behind its page, and tapping an empty area of
/// the page falls through to it; the barrier answers with
/// `SystemSound.play(SystemSoundType.alert)` — the Windows "ding" heard when
/// clicking near the window edges. Covering the whole page with an invisible
/// hit surface keeps those clicks inside the app.
class AppSurface extends StatelessWidget {
  const AppSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.transparent,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SafeArea(bottom: false, child: child),
      ),
    );
  }
}
