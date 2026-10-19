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
                            style: Theme.of(context).textTheme.headlineSmall,
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
                      width: 130,
                      height: 145,
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
                Text(
                  '${tr(context, 'This month’s life')}: ${life.lifePercent}%',
                ),
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
    super.key,
  });
  final PetMood mood;
  final PetProgress progress;
  final int outfit;
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
    label: 'Savings buddy, level ${widget.progress.level}, ${widget.mood.name}',
    child: AnimatedBuilder(
      animation: motion,
      builder: (_, _) => CustomPaint(
        painter: _BuddyPainter(
          widget.mood,
          widget.progress.bodyScale,
          widget.outfit,
          motion.value,
        ),
      ),
    ),
  );
}

class _BuddyPainter extends CustomPainter {
  _BuddyPainter(this.mood, this.growth, this.outfit, this.phase);
  final PetMood mood;
  final double growth, phase;
  final int outfit;
  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height) / 140;
    canvas.translate(
      size.width / 2,
      size.height * .60 + math.sin(phase * math.pi * 2) * 3,
    );
    canvas.scale(unit * growth);
    final paint = Paint();
    canvas.drawOval(
      const Rect.fromLTWH(-46, 48, 92, 12),
      paint..color = const Color(0x18000000),
    );
    final color = outfit == 0
        ? const Color(0xff5ac6ad)
        : HSVColor.fromAHSV(1, (outfit * 67.0) % 360, .42, .86).toColor();
    paint.color = color;
    canvas.drawOval(const Rect.fromLTWH(-51, -56, 102, 108), paint);
    canvas.drawOval(const Rect.fromLTWH(-41, 35, 32, 20), paint);
    canvas.drawOval(const Rect.fromLTWH(9, 35, 32, 20), paint);
    canvas.drawCircle(const Offset(-30, -48), 17, paint);
    canvas.drawCircle(const Offset(30, -48), 17, paint);
    paint.color = const Color(0xff153c38);
    final blink = phase > .91 && phase < .96;
    for (final x in [-18.0, 18.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, -7),
          width: 7,
          height: blink ? 2 : 11,
        ),
        paint,
      );
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final smile = Path()
      ..moveTo(-9, 14)
      ..quadraticBezierTo(0, mood == PetMood.happy ? 25 : 4, 9, 14);
    canvas.drawPath(smile, paint);
    paint.style = PaintingStyle.fill;
    if (mood == PetMood.crying) {
      paint.color = const Color(0xff4ba9ee);
      for (final x in [-22.0, 22.0]) {
        canvas.drawOval(Rect.fromLTWH(x - 4, 3 + phase * 23, 8, 14), paint);
      }
    }
    if (outfit > 0) {
      paint.color = const Color(0xffffcf64);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-43, 22, 86, 13),
          const Radius.circular(6),
        ),
        paint,
      );
      canvas.drawCircle(const Offset(22, 43), 9, paint);
      canvas.drawOval(const Rect.fromLTWH(-45, -62, 90, 13), paint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-29, -88, 58, 30),
          const Radius.circular(8),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BuddyPainter oldDelegate) => true;
}
