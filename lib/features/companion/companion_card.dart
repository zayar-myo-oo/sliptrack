import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/state.dart';
import '../../core/exchange_rate.dart';
import '../../core/models.dart';
import '../../shared/localized_text.dart';
import 'coach_models.dart';
import 'pixel_cat.dart';

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
    this.onTap,
    super.key,
  });
  final VoidCallback? onTap;
  final PetMood mood;
  final PetProgress progress;
  final int outfit;
  final bool compact;
  @override
  State<Buddy> createState() => _BuddyState();
}

class _BuddyState extends State<Buddy> with TickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );

  /// One-shot hop with a floating heart when the cat is tapped.
  late final AnimationController hop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
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
    hop.dispose();
    super.dispose();
  }

  /// Late at night a happy cat naps; tapping it still wakes it for a hop.
  bool get _sleepy {
    final h = DateTime.now().hour;
    return widget.mood == PetMood.happy &&
        !hop.isAnimating &&
        (h >= 23 || h < 6);
  }

  void _pet() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    HapticFeedback.lightImpact();
    hop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cat = Semantics(
      label: 'Savings cat, level ${widget.progress.level}, ${widget.mood.name}',
      child: AnimatedBuilder(
        animation: Listenable.merge([motion, hop]),
        builder: (_, _) {
          final t = hop.value;
          final lift = math.sin(t * math.pi);
          // Squash on take-off and landing, stretch in the air.
          final squash = t < .12
              ? 1 - t * 1.2
              : t > .88
              ? 1 - (1 - t) * 1.2
              : 1 + lift * .06;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(0, -lift * 14),
                  child: Transform.scale(
                    scaleX: 2 - squash,
                    scaleY: squash,
                    alignment: Alignment.bottomCenter,
                    child: CustomPaint(
                      painter: PixelCatPainter(
                        mood: widget.mood,
                        growth: widget.compact
                            ? (widget.progress.bodyScale * .9 + .25).clamp(
                                .7,
                                1.0,
                              )
                            : widget.progress.bodyScale,
                        outfit: widget.outfit,
                        phase: motion.value,
                        sleeping: _sleepy,
                      ),
                    ),
                  ),
                ),
              ),
              if (hop.isAnimating)
                Positioned(
                  top: -6 - t * 26,
                  right: 4,
                  child: Opacity(
                    opacity: (1 - t).clamp(0, 1),
                    child: Transform.scale(
                      scale: .6 + t * .6,
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xffff6b81),
                        size: 22,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
    if (widget.compact) return cat;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _pet();
        widget.onTap?.call();
      },
      child: cat,
    );
  }
}

