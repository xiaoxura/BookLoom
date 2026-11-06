import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../design/theme/app_tokens.dart';
import '../../design/tokens/app_colors.dart';
import '../../design/tokens/app_metrics.dart';
import '../../l10n/app_localizations.dart';
import '../window/window_controls.dart';

/// A quiet, app-drawn title bar.
///
/// The native GTK/Windows title bar is hidden (see `window_service.dart`), so
/// dragging, double-click-to-maximize and the three window buttons live here and
/// follow the design tokens instead of the desktop theme.
///
/// On mobile the whole row collapses to zero height.
class WindowCaption extends StatelessWidget {
  const WindowCaption({super.key});

  @override
  Widget build(BuildContext context) {
    if (!WindowControls.supported) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          // Drag surface. Double click toggles maximize, like every other
          // desktop window.
          Expanded(
            child: GestureDetector(
              // Opaque, not translucent: an empty caption press must stop at
              // the page surface instead of falling through to the route's
              // non-dismissible ModalBarrier, which plays the system alert
              // sound on Windows.
              behavior: HitTestBehavior.opaque,
              onPanStart: (DragStartDetails _) =>
                  WindowControls.startDragging(),
              onDoubleTap: WindowControls.toggleMaximize,
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const _WindowButtons(),
          const SizedBox(width: AppSpacing.md),
        ],
      ),
    );
  }
}

class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _CaptionButton(
          icon: Icons.remove,
          tooltip: l10n.windowMinimize,
          onPressed: WindowControls.minimize,
        ),
        _CaptionButton(
          icon: Icons.crop_square,
          tooltip: l10n.windowMaximize,
          onPressed: WindowControls.toggleMaximize,
        ),
        _CaptionButton(
          icon: Icons.close,
          tooltip: l10n.windowClose,
          onPressed: WindowControls.close,
          danger: true,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final Color background = _hovered
        ? (widget.danger
              ? colors.danger.withValues(alpha: 0.12)
              : colors.ink.withValues(alpha: 0.06))
        : Colors.transparent;
    final Color foreground = widget.danger && _hovered
        ? colors.danger
        : colors.inkSecondary;

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
          onExit: (PointerExitEvent _) => setState(() => _hovered = false),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: Container(
                // Square hit target: a 34x26 box read as a stretched pill next
                // to the round icons.
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, size: 15, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
