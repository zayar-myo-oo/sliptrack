import 'package:flutter/material.dart';
import 'motion.dart';

/// Design tokens shared by every screen. Keep colours here instead of
/// hard-coding them in widgets so light and dark themes stay consistent.
class Palette {
  static const brand = Color(0xff1e4b3a);
  static const brandDeep = Color(0xff143528);
  static const mint = Color(0xffd6ebdf);
  static const income = Color(0xff2e8b57);
  static const expense = Color(0xffc8544b);
  static const warn = Color(0xffc98a1b);

  /// Chart highlight colour that keeps contrast on dark surfaces.
  static Color accent(BuildContext context) =>
      dark(context) ? const Color(0xff7fcf9f) : brand;

  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color bg(BuildContext context) =>
      dark(context) ? const Color(0xff0f1512) : const Color(0xfff4f4ef);
  static Color surface(BuildContext context) =>
      dark(context) ? const Color(0xff1a221e) : Colors.white;
  static Color soft(BuildContext context) =>
      dark(context) ? const Color(0xff243029) : const Color(0xffeef1ec);
  static Color text(BuildContext context) =>
      dark(context) ? const Color(0xffeef2ee) : const Color(0xff15211b);
  static Color muted(BuildContext context) =>
      dark(context) ? const Color(0xff9aa69f) : const Color(0xff6b7770);
  static Color line(BuildContext context) =>
      dark(context) ? const Color(0xff2c3832) : const Color(0xffe7e9e3);
  static Color incomeSoft(BuildContext context) =>
      dark(context) ? const Color(0xff1f3a2b) : const Color(0xffe1f1e7);
  static Color expenseSoft(BuildContext context) =>
      dark(context) ? const Color(0xff3d2421) : const Color(0xfffbe7e4);
}

/// A rounded white surface with an optional tap action.
class Surface extends StatelessWidget {
  const Surface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: onTap == null ? _body(context) : Pressable(child: _body(context)),
  );

  Widget _body(BuildContext context) => Material(
    color: color ?? Palette.surface(context),
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.action, super.key});
  final Widget title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 0, 6),
    child: Row(
      children: [
        Expanded(
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Palette.text(context),
            ),
            child: title,
          ),
        ),
        ?action,
      ],
    ),
  );
}
