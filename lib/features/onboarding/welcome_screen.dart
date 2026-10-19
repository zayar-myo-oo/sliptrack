import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/state.dart';
import '../../shared/design.dart';
import '../companion/coach_models.dart';
import '../companion/companion_card.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeState();
}

class _WelcomeState extends ConsumerState<WelcomeScreen> {
  final pages = PageController();
  int page = 0;

  static const slides = [
    (
      PetMood.happy,
      Icons.document_scanner_outlined,
      'Your slips.\nYour money story.',
      'Snap or import your TrueMoney, KBank and KBZ e-slips. I read them and keep your spending journal for you.',
    ),
    (
      PetMood.worried,
      Icons.pie_chart_outline_rounded,
      'Know where\nit all goes.',
      'Every slip is sorted into food, transport, bills and more. Set budgets and I’ll warn you before you overspend.',
    ),
    (
      PetMood.happy,
      Icons.lock_outline_rounded,
      'Private by\ndesign.',
      'Reading happens on your phone. Records are encrypted, there’s no bank login, and nothing is uploaded.',
    ),
  ];

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    final prefs = ref.read(preferencesProvider);
    if (prefs.values['since'] == null) {
      await prefs.update('since', DateTime.now().millisecondsSinceEpoch);
    }
    await prefs.update('onboarded', true);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final last = page == slides.length - 1;
    final progress = PetProgress(xpMicros: 0, highestMilestones: 9);
    return Scaffold(
      backgroundColor: Palette.brandDeep,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
              child: Row(
                children: [
                  Text(
                    '0${page + 1} / 0${slides.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < slides.length; i++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: i <= page
                                    ? Palette.mint
                                    : Colors.white.withValues(alpha: .2),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: finish,
                    child: const LText('Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pages,
                itemCount: slides.length,
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => page = i);
                },
                itemBuilder: (_, i) {
                  final s = slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        Center(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .06),
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Buddy(mood: s.$1, progress: progress),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 18,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Palette.mint,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Icon(s.$2, color: Palette.brandDeep),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        LText(
                          s.$3,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 16),
                        LText(
                          s.$4,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Palette.brandDeep,
                      minimumSize: const Size(48, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: last
                        ? finish
                        : () => pages.nextPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LText(last ? 'Get started' : 'Next'),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
                  ),
                  if (last)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      onPressed: () => context.push('/accounts'),
                      child: const LText('Add my local account profiles'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
