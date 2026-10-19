import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/state.dart';
import '../../core/exchange_rate.dart';
import '../../core/models.dart';
import '../../shared/localized_text.dart';
import 'coach_models.dart';

class CompanionCard extends ConsumerWidget {
  const CompanionCard({required this.totals, super.key});
  final Map<String, Totals> totals;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coach = ref.watch(coachProvider),
        prefs = ref.watch(preferencesProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([coach, prefs]),
      builder: (_, _) {
        final life = BudgetLife.fromTotals(
          totals,
          prefs.values['mmkPerThbMicros'] ?? defaultMmkPerThbMicros,
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const LText('Your savings buddy'),
                          Text(
                            'Lv. ${coach.progress.level} / 10',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          LText(
                            life.mood == PetMood.crying
                                ? 'A little care, one step at a time.'
                                : life.mood == PetMood.worried
                                ? 'Let’s slow down spending.'
                                : 'Growing together!',
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 98,
                      height: 106,
                      child: Buddy(
                        mood: life.mood,
                        progress: coach.progress,
                        outfit: coach.outfit,
                      ),
                    ),
                  ],
                ),
                LinearProgressIndicator(
                  value: life.lifePercent / 100,
                  minHeight: 9,
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(height: 8),
                Text('${tr(context, 'Available money')}: ${life.lifePercent}%'),
                TextButton(
                  onPressed: () => context.push('/companion'),
                  child: const LText('Savings & companion'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class Buddy extends StatefulWidget {
  const Buddy({
    required this.mood,
    required this.progress,
    this.outfit = 0,
    this.compact = false,
    super.key,
  });
  final PetMood mood;
  final PetProgress progress;
  final int outfit;
  final bool compact;
  @override
  State<Buddy> createState() => _BuddyState();
}

class _BuddyState extends State<Buddy> with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.stop();
    } else {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Savings cat, level ${widget.progress.level}, ${widget.mood.name}',
    child: AnimatedBuilder(
      animation: motion,
      builder: (_, _) => CustomPaint(
        painter: _BuddyPainter(
          widget.mood,
          widget.compact
              ? (widget.progress.bodyScale * .9 + .25).clamp(.7, 1.0)
              : widget.progress.bodyScale,
          widget.outfit,
          motion.value,
        ),
      ),
    ),
  );
}

/// A chubby cream cat with a ginger tabby crown. The head is drawn large so
/// the face still reads at bottom-navigation size; mood changes the eyes,
/// brows and mouth, and unlocked outfits add a scarf and a coin badge.
class _BuddyPainter extends CustomPainter {
  _BuddyPainter(this.mood, this.growth, this.outfit, this.phase);
  final PetMood mood;
  final double growth, phase;
  final int outfit;

  static const fur = Color(0xfffff3e2);
  static const ginger = Color(0xfff2a65a);
  static const gingerDark = Color(0xffe08a3c);
  static const outline = Color(0xff4a3426);
  static const innerEar = Color(0xffffc2c0);
  static const blush = Color(0x66ff8f8f);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height) / 150;
    final wave = math.sin(phase * math.pi * 2);
    canvas.translate(size.width / 2, size.height * .56 + wave * 2.5);
    canvas.scale(unit * growth);
    final p = Paint()..isAntiAlias = true;
    final line = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Ground shadow.
    p.color = const Color(0x1a000000);
    canvas.drawOval(const Rect.fromLTWH(-42, 60, 84, 10), p);

    // Tail: a soft ginger curl that sways.
    final tail = Path()
      ..moveTo(28, 50)
      ..cubicTo(64, 54, 70 + wave * 6, 18, 54 + wave * 6, 4);
    canvas.drawPath(
      tail,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      tail,
      Paint()
        ..color = ginger
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10.5
        ..strokeCap = StrokeCap.round,
    );

    // Body.
    const body = Rect.fromLTWH(-36, 14, 72, 54);
    p.color = fur;
    canvas.drawOval(body, p);
    canvas.drawOval(body, line);
    // Belly patch.
    p.color = Colors.white;
    canvas.drawOval(const Rect.fromLTWH(-20, 30, 40, 32), p);

    // Feet.
    for (final x in [-20.0, 20.0]) {
      final foot = Rect.fromCenter(
        center: Offset(x, 64),
        width: 24,
        height: 13,
      );
      p.color = fur;
      canvas.drawOval(foot, p);
      canvas.drawOval(foot, line);
    }

    // Ears, behind the head.
    for (final side in [-1.0, 1.0]) {
      final ear = Path()
        ..moveTo(side * 48, -26)
        ..quadraticBezierTo(side * 58, -70, side * 40, -74)
        ..quadraticBezierTo(side * 26, -66, side * 14, -50)
        ..close();
      p.color = ginger;
      canvas.drawPath(ear, p);
      canvas.drawPath(ear, line);
      p.color = innerEar;
      canvas.drawPath(
        Path()
          ..moveTo(side * 42, -38)
          ..quadraticBezierTo(side * 48, -62, side * 39, -64)
          ..quadraticBezierTo(side * 30, -58, side * 24, -50)
          ..close(),
        p,
      );
    }

    // Head.
    const head = Rect.fromLTWH(-56, -64, 112, 92);
    p.color = fur;
    canvas.drawOval(head, p);
    // Ginger crown with three tabby stripes, clipped to the head.
    canvas.save();
    canvas.clipPath(Path()..addOval(head));
    p.color = ginger;
    canvas.drawOval(const Rect.fromLTWH(-64, -92, 128, 70), p);
    p.color = gingerDark;
    for (final x in [-14.0, 0.0, 14.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, -56), width: 6, height: 20),
          const Radius.circular(3),
        ),
        p,
      );
    }
    canvas.restore();
    canvas.drawOval(head, line);

    // Cheeks.
    p.color = blush;
    for (final x in [-32.0, 32.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 2), width: 18, height: 10),
        p,
      );
    }

    // Eyes.
    final blink = phase > .9 && phase < .95;
    for (final side in [-1.0, 1.0]) {
      final c = Offset(side * 20, -12);
      if (blink || mood == PetMood.happy && phase > .5 && phase < .56) {
        canvas.drawLine(c.translate(-6, 0), c.translate(6, 0), line);
      } else if (mood == PetMood.crying) {
        // Squeezed "> <" eyes.
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - side * 6, c.dy - 6)
            ..lineTo(c.dx + side * 4, c.dy)
            ..lineTo(c.dx - side * 6, c.dy + 6),
          line,
        );
      } else {
        p.color = outline;
        canvas.drawOval(Rect.fromCenter(center: c, width: 15, height: 18), p);
        p.color = Colors.white;
        canvas.drawCircle(c.translate(-3, -4), 3.6, p);
        canvas.drawCircle(c.translate(3, 4), 1.6, p);
      }
      if (mood != PetMood.happy) {
        // Brows tilt up toward the middle when worried or sad.
        canvas.drawLine(Offset(side * 28, -30), Offset(side * 12, -34), line);
      }
    }

    // Nose and mouth.
    p.color = const Color(0xffff8a8a);
    canvas.drawPath(
      Path()
        ..moveTo(-4.5, 2)
        ..quadraticBezierTo(0, 0, 4.5, 2)
        ..quadraticBezierTo(0, 8, -4.5, 2),
      p,
    );
    if (mood == PetMood.happy) {
      // Open smile.
      final mouth = Path()
        ..moveTo(-9, 8)
        ..quadraticBezierTo(0, 22, 9, 8)
        ..close();
      p.color = const Color(0xffd9606a);
      canvas.drawPath(mouth, p);
      canvas.drawPath(mouth, line);
    } else if (mood == PetMood.worried) {
      canvas.drawPath(
        Path()
          ..moveTo(-8, 12)
          ..quadraticBezierTo(-4, 9, 0, 12)
          ..quadraticBezierTo(4, 15, 8, 12),
        line,
      );
      // Sweat drop.
      p.color = const Color(0xff8ccaf5);
      canvas.drawPath(
        Path()
          ..moveTo(44, -38)
          ..quadraticBezierTo(38, -26, 44, -24)
          ..quadraticBezierTo(50, -26, 44, -38),
        p,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(-8, 15)
          ..quadraticBezierTo(0, 8, 8, 15),
        line,
      );
      p.color = const Color(0xff7cc4f4);
      for (final x in [-22.0, 22.0]) {
        canvas.drawOval(Rect.fromLTWH(x - 3.5, -2 + phase * 20, 7, 11), p);
      }
    }

    // Whiskers.
    final whisker = Paint()
      ..color = outline.withValues(alpha: .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final side in [-1.0, 1.0]) {
      canvas.drawLine(Offset(side * 42, -2), Offset(side * 62, -6), whisker);
      canvas.drawLine(Offset(side * 42, 5), Offset(side * 62, 7), whisker);
    }

    // Paws hugging a coin.
    p.color = const Color(0xffffcf5a);
    canvas.drawCircle(const Offset(0, 40), 11, p);
    canvas.drawCircle(const Offset(0, 40), 11, line);
    p.color = const Color(0xffe7a93a);
    canvas.drawCircle(const Offset(0, 40), 5.5, p);
    for (final x in [-11.0, 11.0]) {
      final paw = Rect.fromCenter(center: Offset(x, 42), width: 15, height: 12);
      p.color = fur;
      canvas.drawOval(paw, p);
      canvas.drawOval(paw, line);
    }

    // Unlocked outfit: a scarf in a colour that changes per outfit.
    if (outfit > 0) {
      final scarf = outfit == 1
          ? const Color(0xff2e8b57)
          : HSVColor.fromAHSV(1, (outfit * 67.0) % 360, .55, .75).toColor();
      p.color = scarf;
      final band = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-38, 18, 76, 12),
        const Radius.circular(6),
      );
      canvas.drawRRect(band, p);
      canvas.drawRRect(band, line);
      final tailEnd = RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 24, 12, 22),
        const Radius.circular(5),
      );
      canvas.drawRRect(tailEnd, p);
      canvas.drawRRect(tailEnd, line);
    }
  }

  @override
  bool shouldRepaint(covariant _BuddyPainter oldDelegate) => true;
}
