import 'package:flutter/material.dart';
import '../core/models.dart';
import 'privacy.dart';

/// Shared motion so every screen moves the same way. All helpers settle
/// instantly when the system "reduce motion" setting is on.
class Motion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 900);
  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Fades and lifts its child into place once, after a short staggered delay.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({required this.child, this.index = 0, super.key});
  final Widget child;
  final int index;
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  // The stagger is part of the animation itself (no timers), so tests and
  // route changes never leave work pending.
  late final int delay = 22 * widget.index.clamp(0, 6);
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: Motion.medium + Duration(milliseconds: delay),
  );
  late final Animation<double> t = CurvedAnimation(
    parent: c,
    curve: Interval(
      delay / (Motion.medium.inMilliseconds + delay),
      1,
      curve: Motion.curve,
    ),
  );
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) return;
    started = true;
    if (Motion.reduced(context)) {
      c.value = 1;
    } else {
      c.forward();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: t,
    child: AnimatedBuilder(
      animation: t,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 10 * (1 - t.value)),
        child: child,
      ),
      child: widget.child,
    ),
  );
}

/// Counts from the previous value to [minor] whenever it changes.
class CountUpMoney extends StatefulWidget {
  const CountUpMoney(
    this.minor,
    this.currency, {
    this.prefix = '',
    this.style,
    super.key,
  });
  final int minor;
  final String currency, prefix;
  final TextStyle? style;
  @override
  State<CountUpMoney> createState() => _CountUpMoneyState();
}

class _CountUpMoneyState extends State<CountUpMoney> {
  int from = 0;
  @override
  void didUpdateWidget(CountUpMoney old) {
    super.didUpdateWidget(old);
    if (old.minor != widget.minor) from = old.minor;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: hideAmounts,
    builder: (context, hidden, _) => hidden
        ? Text(
            '${widget.prefix}$maskedAmount ${widget.currency}',
            style: widget.style,
          )
        : _counter(context),
  );

  Widget _counter(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(widget.minor),
    tween: Tween(begin: from.toDouble(), end: widget.minor.toDouble()),
    duration: Motion.reduced(context) ? Duration.zero : Motion.slow,
    curve: Curves.easeOutExpo,
    builder: (_, v, _) => Text(
      '${widget.prefix}${money(v.round(), widget.currency)}',
      style: widget.style,
    ),
  );
}

/// A rounded progress bar that grows to [value] and animates later changes.
class GrowBar extends StatelessWidget {
  const GrowBar({
    required this.value,
    required this.color,
    required this.background,
    this.height = 8,
    super.key,
  });
  final double value, height;
  final Color color, background;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
    duration: Motion.reduced(context) ? Duration.zero : Motion.slow,
    curve: Motion.curve,
    builder: (_, v, _) => ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: v,
        minHeight: height,
        color: color,
        backgroundColor: background,
      ),
    ),
  );
}

/// Shrinks slightly while pressed, then springs back.
class Pressable extends StatefulWidget {
  const Pressable({required this.child, super.key});
  final Widget child;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => down = true),
    onPointerUp: (_) => setState(() => down = false),
    onPointerCancel: (_) => setState(() => down = false),
    child: AnimatedScale(
      scale: down ? .95 : 1,
      duration: Motion.fast,
      curve: Curves.easeOutBack,
      child: widget.child,
    ),
  );
}

/// Wraps each child so a column of cards enters one after another.
List<Widget> staggered(List<Widget> children) => [
  for (var i = 0; i < children.length; i++)
    FadeSlideIn(index: i, child: children[i]),
];
