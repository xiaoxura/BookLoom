import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_metrics.dart';

/// A labelled, read-only Material 3 menu for choosing one setting value.
class AppSelectField<T> extends StatefulWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.initialSelection,
    required this.entries,
    required this.onSelected,
  });

  final String label;
  final T initialSelection;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onSelected;

  @override
  State<AppSelectField<T>> createState() => _AppSelectFieldState<T>();
}

class _AppSelectFieldState<T> extends State<AppSelectField<T>> {
  final MenuController _menuController = MenuController();
  bool _menuOpen = false;
  bool _syncScheduled = false;

  void _syncMenuOpen() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final bool isOpen = _menuController.isOpen;
      if (_menuOpen != isOpen) {
        setState(() => _menuOpen = isOpen);
      }
    });
  }

  Widget _chevron(IconData icon, Color color) => Builder(
    builder: (BuildContext context) {
      // MenuAnchor publishes every open/close, including outside taps and
      // selections, to descendants through its inherited menu state.
      final bool isOpen = MenuController.maybeIsOpenOf(context) ?? false;
      if (isOpen != _menuOpen) _syncMenuOpen();
      return Icon(icon, size: 20, color: color);
    },
  );

  Future<bool> _handleBack() async {
    if (!_menuController.isOpen) return false;
    _menuController.close();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final chevronColor = colors.inkSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.label,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: colors.ink, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        PopScope<Object?>(
          canPop: !_menuOpen,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop && _menuController.isOpen) _menuController.close();
          },
          child: BackButtonListener(
            onBackButtonPressed: _handleBack,
            child: Semantics(
              container: true,
              label: widget.label,
              child: DropdownMenu<T>(
                menuController: _menuController,
                initialSelection: widget.initialSelection,
                expandedInsets: EdgeInsets.zero,
                selectOnly: true,
                enableSearch: false,
                trailingIcon: _chevron(Icons.expand_more, chevronColor),
                selectedTrailingIcon: _chevron(Icons.expand_less, chevronColor),
                dropdownMenuEntries: <DropdownMenuEntry<T>>[
                  for (final entry in widget.entries)
                    DropdownMenuEntry<T>(
                      value: entry.value,
                      label: entry.label,
                      labelWidget: entry.labelWidget,
                      leadingIcon: entry.leadingIcon,
                      trailingIcon: entry.value == widget.initialSelection
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: colors.accent,
                            )
                          : entry.trailingIcon,
                      enabled: entry.enabled,
                      style: entry.value == widget.initialSelection
                          ? (entry.style ?? const ButtonStyle()).copyWith(
                              backgroundColor: WidgetStatePropertyAll(
                                colors.accentSoft,
                              ),
                              foregroundColor: WidgetStatePropertyAll(
                                colors.accent,
                              ),
                              iconColor: WidgetStatePropertyAll(colors.accent),
                              padding: const WidgetStatePropertyAll(
                                EdgeInsetsDirectional.only(
                                  start: AppSpacing.lg,
                                  end: AppSpacing.md,
                                ),
                              ),
                            )
                          : entry.style,
                    ),
                ],
                onSelected: widget.onSelected,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
