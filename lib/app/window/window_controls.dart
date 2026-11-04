import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Thin wrapper over `window_manager` (native API) so the UI never touches the
/// plugin directly and tests stay safe when no native window exists.
///
/// The native title bar is hidden on desktop; dragging, maximizing, closing and
/// edge resizing are re-created in Flutter (see [DesktopWindowFrame]).
abstract final class WindowControls {
  static bool get supported =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  /// Resolves the current window, or null when there is none (tests, mobile).
  static Window? _current() {
    if (!supported) return null;
    try {
      return WindowManager.instance.getCurrent();
    } on Object {
      return null;
    }
  }

  /// Applies the frameless look and initial geometry. Call once at startup.
  static void configure() {
    final Window? window = _current();
    if (window == null) return;
    try {
      // Linux is already frameless in the GTK runner; setting the style again
      // there makes GTK reserve shadow margins. Windows/macOS need the call.
      if (Platform.isWindows || Platform.isMacOS) {
        window.titleBarStyle = TitleBarStyle.hidden;
      }
      // Size comes from the platform runner (1440×900); resizing here at
      // startup races the first frame and leaves the Flutter view at the old
      // metrics. Only the minimum and the title are set from Dart.
      window.title = '书织 Bookloom';
      window.minimumSize = const Size(820, 600).toNative();
      window.center();
      window.show();
      window.focus();
    } on Object {
      // Keep the native chrome if anything goes wrong; never block startup.
    }
  }

  static void minimize() {
    try {
      _current()?.minimize();
    } on Object {
      // Best effort.
    }
  }

  static void close() {
    try {
      _current()?.close();
    } on Object {
      // Best effort.
    }
  }

  static void toggleMaximize() {
    final Window? window = _current();
    if (window == null) return;
    try {
      if (window.isMaximized) {
        window.unmaximize();
      } else {
        window.maximize();
      }
    } on Object {
      // Best effort.
    }
  }

  static void startDragging() {
    try {
      _current()?.startDragging();
    } on Object {
      // Best effort.
    }
  }

  static void startResizing(ResizeEdge edge) {
    try {
      _current()?.startResizing(edge);
    } on Object {
      // Best effort.
    }
  }
}

/// Invisible resize grips around the window edge.
///
/// A frameless window loses the OS-provided resize border, so we put a few
/// pixels of hot zone on each edge and hand the drag back to GTK/Win32.
class DesktopWindowFrame extends StatelessWidget {
  const DesktopWindowFrame({super.key, required this.child});

  final Widget child;

  static const double _edge = 6;
  static const double _corner = 14;

  @override
  Widget build(BuildContext context) {
    if (!WindowControls.supported) return child;

    Widget grip({
      required ResizeEdge edge,
      required MouseCursor cursor,
      double? left,
      double? top,
      double? right,
      double? bottom,
      double? width,
      double? height,
    }) {
      return Positioned(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (DragStartDetails _) =>
                WindowControls.startResizing(edge),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    return Stack(
      children: <Widget>[
        child,
        // Edges.
        grip(
          edge: ResizeEdge.top,
          cursor: SystemMouseCursors.resizeUpDown,
          top: 0,
          left: _corner,
          right: _corner,
          height: _edge,
        ),
        grip(
          edge: ResizeEdge.bottom,
          cursor: SystemMouseCursors.resizeUpDown,
          bottom: 0,
          left: _corner,
          right: _corner,
          height: _edge,
        ),
        grip(
          edge: ResizeEdge.left,
          cursor: SystemMouseCursors.resizeLeftRight,
          left: 0,
          top: _corner,
          bottom: _corner,
          width: _edge,
        ),
        grip(
          edge: ResizeEdge.right,
          cursor: SystemMouseCursors.resizeLeftRight,
          right: 0,
          top: _corner,
          bottom: _corner,
          width: _edge,
        ),
        // Corners.
        grip(
          edge: ResizeEdge.topLeft,
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          top: 0,
          left: 0,
          width: _corner,
          height: _corner,
        ),
        grip(
          edge: ResizeEdge.topRight,
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          top: 0,
          right: 0,
          width: _corner,
          height: _corner,
        ),
        grip(
          edge: ResizeEdge.bottomLeft,
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          bottom: 0,
          left: 0,
          width: _corner,
          height: _corner,
        ),
        grip(
          edge: ResizeEdge.bottomRight,
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          bottom: 0,
          right: 0,
          width: _corner,
          height: _corner,
        ),
      ],
    );
  }
}
