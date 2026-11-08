import 'package:bookloom/core/model/layout_options.dart';
import 'package:flutter/material.dart';

class LayoutParagraph extends StatelessWidget {
  const LayoutParagraph({
    super.key,
    required this.text,
    required this.layout,
    required this.style,
  });

  final String text;
  final LayoutOptions layout;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final fontSize =
        style.fontSize ?? DefaultTextStyle.of(context).style.fontSize!;
    final scaledFontSize = MediaQuery.textScalerOf(context).scale(fontSize);
    return Padding(
      padding: EdgeInsets.only(
        bottom: scaledFontSize * layout.paragraphSpacing,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (layout.indent)
              WidgetSpan(
                alignment: PlaceholderAlignment.bottom,
                child: SizedBox(width: scaledFontSize * 2),
              ),
            TextSpan(text: text),
          ],
        ),
        semanticsLabel: text,
        textAlign: layout.justify ? TextAlign.justify : TextAlign.start,
        style: style.copyWith(fontSize: scaledFontSize),
        textScaler: TextScaler.noScaling,
      ),
    );
  }
}
