import '../../shared/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/state.dart';
import '../../shared/components.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    return Scaffold(
      body: SafeArea(
        child: PageBody(prefs.text('Welcome to SlipTrack'), [
          const SizedBox(height: 32),
          const Icon(
            Icons.receipt_long_rounded,
            size: 88,
            color: Color(0xff087f72),
          ),
          const SizedBox(height: 32),
          LText(
            'Your slips.\nYour money story.',
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          const LText(
            'Turn saved bank e-slips into a private spending journal. TrueMoney, KBank and KBZ, together on your device.',
          ),
          const SizedBox(height: 24),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LText(
                    'Private by design',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  LText(
                    'On-device OCR · Encrypted records · No bank login\n\nOnly photos you authorize are accessible. Import selected photos without granting broad library access.',
                  ),
                  SizedBox(height: 12),
                  LText(
                    'Automatic detection runs while the system permits. iOS does not monitor photos while terminated. Android defers work under battery restrictions. Receipts are tracking evidence, not verified balances.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (prefs.values['since'] == null) {
                await prefs.update(
                  'since',
                  DateTime.now().millisecondsSinceEpoch,
                );
              }
              await prefs.update('onboarded', true);
              if (context.mounted) context.go('/scan');
            },
            child: const LText('Get started'),
          ),
          TextButton(
            onPressed: () => context.push('/accounts'),
            child: const LText('Add my local account profiles'),
          ),
        ]),
      ),
    );
  }
}
