import 'package:flutter/material.dart';
import '../core/strings.dart';

String tr(BuildContext context, String value) =>
    translate(Localizations.localeOf(context).languageCode, value);

class LText extends StatelessWidget {
  const LText(
    this.data, {
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    super.key,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  @override
  Widget build(BuildContext context) => Text(
    tr(context, data),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );
}
