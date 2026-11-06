import 'package:flutter/animation.dart';

/// 4pt spacing scale. Every gap in the app comes from here.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;
}

/// Corner radii. Glass and cards use [lg]; controls use [md].
abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 16;
  static const double xl = 22;
  static const double pill = 999;
}

/// Motion tokens. Keep durations short: a notebook should feel like paper,
/// not like a slide deck.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration page = Duration(milliseconds: 240);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasise = Curves.easeInOutCubic;
}

/// Layout constants shared by the shell and pages.
abstract final class AppLayout {
  /// Below this width the sidebar auto-collapses to its icon rail.
  static const double railBreakpoint = 960;

  /// Narrower than this the rail collapses; a little wider than
  /// [railBreakpoint] it expands again, so dragging the window edge does not
  /// flap between the two states.
  static const double railAutoCollapseWidth = 1040;

  /// At or above this width the rail auto-expands.
  static const double railAutoExpandWidth = 1120;

  /// Sidebar width on desktop.
  static const double sidebarWidth = 220;

  /// Sidebar width once collapsed; icons only, the rail keeps its identity.
  static const double sidebarCollapsedWidth = 56;

  /// Content column maximum width; keeps prose readable on wide monitors.
  static const double contentMaxWidth = 1080;

  /// Gutter around the floating shell.
  static const double shellGutter = 16;

  /// Horizontal padding inside a page.
  static const double pagePadding = 32;

  /// The glass navigation pane excludes the device's system insets.
  static const double bottomBarHeight = 68;

  /// Below this width, segmented theme labels take priority over their icons.
  static const double themeControlIconBreakpoint = 400;
}
